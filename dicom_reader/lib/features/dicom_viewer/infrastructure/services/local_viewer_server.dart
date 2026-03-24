import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../application/models/viewer_study_session.dart';
import '../../domain/entities/dicom_models.dart';

const String _viewerAssetPrefix = 'assets/cornerstone_viewer';
const String _viewerPathPrefix = '/viewer';
const String _dicomPathPrefix = '/dicom';

ContentType getContentTypeForPath(String path) {
  final lower = path.toLowerCase().split('?').first;
  if (lower.endsWith('.html')) {
    return ContentType.html;
  }
  if (lower.endsWith('.js')) {
    return ContentType('application', 'javascript', charset: 'utf-8');
  }
  if (lower.endsWith('.css')) {
    return ContentType('text', 'css', charset: 'utf-8');
  }
  if (lower.endsWith('.json')) {
    return ContentType.json;
  }
  if (lower.endsWith('.wasm')) {
    return ContentType('application', 'wasm');
  }
  if (lower.endsWith('.png')) {
    return ContentType('image', 'png');
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return ContentType('image', 'jpeg');
  }
  if (lower.endsWith('.ico')) {
    return ContentType('image', 'x-icon');
  }
  return ContentType('application', 'octet-stream');
}

/// Serves the local Cornerstone viewer and DICOM files through loopback HTTP.
///
/// - `/viewer/*` -> bundled web assets from Flutter assets.
/// - `/dicom/<token>` -> streamed local or proxied remote DICOM bytes.
class LocalViewerServer {
  HttpServer? _server;
  int _tokenSeed = 0;
  final Map<String, _DicomObjectSource> _tokenToSource =
      <String, _DicomObjectSource>{};
  final Map<String, Uint8List> _assetCache = <String, Uint8List>{};

  Future<void> ensureStarted() async {
    if (_server != null) {
      return;
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server!.forEach(_handleRequest));
  }

  Future<ViewerStudySession> registerBundle(DicomStudyBundle bundle) async {
    await ensureStarted();

    const maxImagesPerSeries = 3000;
    final payloads = <String, ViewerSeriesPayload>{};

    for (final study in bundle.studies) {
      for (final series in study.series) {
        final imageIds = <String>[];
        final instances = series.instances;
        final take = instances.length > maxImagesPerSeries
            ? maxImagesPerSeries
            : instances.length;

        for (var i = 0; i < take; i++) {
          try {
            final instance = instances[i];
            final source = _resolveSource(instance);
            if (source == null) {
              continue;
            }

            final token = _encodeToken(
              '${instance.filePath}|${instance.sopInstanceUid}|$i',
            );
            _tokenToSource[token] = source;
            imageIds.add(
              'wadouri:${_rootUri.resolve('$_dicomPathPrefix/$token')}',
            );
          } catch (_) {
            // Skip problematic instances so the series can still load.
          }
        }

        payloads[series.seriesInstanceUid] = ViewerSeriesPayload(
          studyInstanceUid: study.studyInstanceUid,
          seriesInstanceUid: series.seriesInstanceUid,
          imageIds: imageIds,
        );
      }
    }

    final viewerUrl = _rootUri
        .resolve(
          '$_viewerPathPrefix/index.html?v=${DateTime.now().microsecondsSinceEpoch}',
        )
        .toString();

    return ViewerStudySession(viewerUrl: viewerUrl, seriesPayloads: payloads);
  }

  _DicomObjectSource? _resolveSource(DicomInstance instance) {
    final remoteWadoUri = instance.remoteWadoUri;
    if (remoteWadoUri != null && remoteWadoUri.isNotEmpty) {
      final parsed = Uri.tryParse(remoteWadoUri);
      if (parsed != null) {
        return _DicomObjectSource(
          remoteUri: parsed,
          remoteHeaders: instance.remoteHeaders,
        );
      }
    }

    if (instance.filePath.isEmpty) {
      return null;
    }

    return _DicomObjectSource(localFilePath: instance.filePath);
  }

  Uri get _rootUri {
    final server = _server;
    if (server == null) {
      throw StateError('Viewer server has not started yet.');
    }
    return Uri.parse('http://${server.address.host}:${server.port}');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final pathSegments = request.uri.pathSegments;

      if (path == '/favicon.ico' || path == '/favicon.ico/') {
        request.response.statusCode = HttpStatus.noContent;
        _applyNoCacheHeaders(request.response);
        await request.response.close();
        return;
      }

      if (path == _viewerPathPrefix ||
          path == '$_viewerPathPrefix/' ||
          path.startsWith('$_viewerPathPrefix/')) {
        await _serveViewerAsset(request, path);
        return;
      }

      if (pathSegments.length >= 2 &&
          pathSegments.first == _dicomPathPrefix.substring(1) &&
          pathSegments[1].isNotEmpty) {
        await _serveDicomFile(request, pathSegments[1]);
        return;
      }

      if (path.isEmpty || path == '/') {
        request.response
          ..statusCode = HttpStatus.temporaryRedirect
          ..headers.set(
            HttpHeaders.locationHeader,
            '$_viewerPathPrefix/index.html?v=${DateTime.now().microsecondsSinceEpoch}',
          );
        _applyNoCacheHeaders(request.response);
        await request.response.close();
        return;
      }

      await _replyNotFound(request);
    } catch (e, st) {
      await _replyServerError(request, e, st);
    }
  }

  Future<void> _serveViewerAsset(HttpRequest request, String path) async {
    String relativePath;
    if (path == _viewerPathPrefix || path == '$_viewerPathPrefix/') {
      relativePath = 'index.html';
    } else if (path.startsWith('$_viewerPathPrefix/')) {
      relativePath = path.substring(_viewerPathPrefix.length + 1);
      if (relativePath.isEmpty) {
        relativePath = 'index.html';
      }
    } else {
      relativePath = 'index.html';
    }

    relativePath = relativePath.replaceAll('\\', '/').trim();
    if (relativePath.startsWith('/')) {
      relativePath = relativePath.substring(1);
    }
    if (relativePath.endsWith('/')) {
      relativePath = '${relativePath}index.html';
    }

    if (!_isSafeRelativePath(relativePath)) {
      await _replyNotFound(request);
      return;
    }

    final assetPath = '$_viewerAssetPrefix/$relativePath';
    Uint8List bytes = _assetCache[assetPath] ?? Uint8List(0);

    if (bytes.isEmpty) {
      ByteData data;
      try {
        data = await rootBundle.load(assetPath);
      } catch (_) {
        await _replyNotFound(request);
        return;
      }
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      _assetCache[assetPath] = bytes;
    }

    var responseBytes = bytes;
    if (relativePath == 'index.html') {
      final version = DateTime.now().microsecondsSinceEpoch.toString();
      final html = utf8.decode(bytes, allowMalformed: true);
      final withScriptVersion = html.replaceFirstMapped(
        RegExp(r'src="(/viewer/assets/[^"]+\.js)"'),
        (match) => 'src="${match.group(1)}?v=$version"',
      );
      final withStyleVersion = withScriptVersion.replaceFirstMapped(
        RegExp(r'href="(/viewer/assets/[^"]+\.css)"'),
        (match) => 'href="${match.group(1)}?v=$version"',
      );
      responseBytes = Uint8List.fromList(utf8.encode(withStyleVersion));
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = getContentTypeForPath(relativePath)
      ..headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    _applyNoCacheHeaders(request.response);
    request.response.add(responseBytes);
    await request.response.close();
  }

  Future<void> _serveDicomFile(HttpRequest request, String token) async {
    final source = _tokenToSource[token];
    if (source == null) {
      await _replyNotFound(request);
      return;
    }

    if (source.localFilePath != null) {
      await _serveLocalDicom(request, source.localFilePath!);
      return;
    }

    if (source.remoteUri != null) {
      await _serveRemoteDicom(request, source);
      return;
    }

    await _replyNotFound(request);
  }

  Future<void> _serveLocalDicom(HttpRequest request, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      await _replyNotFound(request);
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('application', 'dicom')
      ..headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    _applyNoCacheHeaders(request.response);
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<void> _serveRemoteDicom(
    HttpRequest request,
    _DicomObjectSource source,
  ) async {
    final remoteUri = source.remoteUri;
    if (remoteUri == null) {
      await _replyNotFound(request);
      return;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30);

    try {
      final upstreamRequest = await client.getUrl(remoteUri);
      upstreamRequest.headers.set(
        HttpHeaders.acceptHeader,
        'application/dicom',
      );
      for (final header in source.remoteHeaders.entries) {
        upstreamRequest.headers.set(header.key, header.value);
      }

      final upstreamResponse = await upstreamRequest.close();
      if (upstreamResponse.statusCode < 200 ||
          upstreamResponse.statusCode >= 300) {
        request.response
          ..statusCode = HttpStatus.badGateway
          ..headers.contentType = ContentType.text;
        _applyNoCacheHeaders(request.response);
        request.response.write(
          'Remote WADO request failed (${upstreamResponse.statusCode}).',
        );
        await request.response.close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('application', 'dicom')
        ..headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
      _applyNoCacheHeaders(request.response);

      await request.response.addStream(upstreamResponse);
      await request.response.close();
    } catch (_) {
      request.response
        ..statusCode = HttpStatus.badGateway
        ..headers.contentType = ContentType.text;
      _applyNoCacheHeaders(request.response);
      request.response.write('Could not reach remote WADO endpoint.');
      await request.response.close();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _replyNotFound(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.notFound
      ..headers.contentType = ContentType.text;
    _applyNoCacheHeaders(request.response);
    await request.response.close();
  }

  Future<void> _replyServerError(
    HttpRequest request,
    Object error,
    StackTrace stackTrace,
  ) async {
    request.response
      ..statusCode = HttpStatus.internalServerError
      ..headers.contentType = ContentType.text;
    _applyNoCacheHeaders(request.response);
    try {
      request.response.write('Internal server error.');
    } catch (_) {
      // Best effort.
    }
    await request.response.close();
  }

  String _encodeToken(String seed) {
    _tokenSeed += 1;
    final raw = '$seed|$_tokenSeed|${DateTime.now().microsecondsSinceEpoch}';
    return base64UrlEncode(utf8.encode(raw));
  }

  bool _isSafeRelativePath(String relativePath) {
    if (relativePath.startsWith('/') ||
        relativePath.contains('..') ||
        relativePath.contains(':')) {
      return false;
    }
    return true;
  }

  void _applyNoCacheHeaders(HttpResponse response) {
    response.headers
      ..set(
        HttpHeaders.cacheControlHeader,
        'no-store, no-cache, must-revalidate, max-age=0',
      )
      ..set(HttpHeaders.pragmaHeader, 'no-cache')
      ..set(HttpHeaders.expiresHeader, '0');
  }

  void dispose() {
    _server?.close(force: true);
    _server = null;
    _tokenToSource.clear();
    _assetCache.clear();
  }
}

class _DicomObjectSource {
  const _DicomObjectSource({
    this.localFilePath,
    this.remoteUri,
    this.remoteHeaders = const <String, String>{},
  });

  final String? localFilePath;
  final Uri? remoteUri;
  final Map<String, String> remoteHeaders;
}
