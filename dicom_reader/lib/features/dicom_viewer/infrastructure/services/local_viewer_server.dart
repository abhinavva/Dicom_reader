import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../../core/services/app_logger.dart';
import '../../application/models/viewer_study_session.dart';
import '../../domain/entities/dicom_models.dart';
import '../../domain/services/viewer_server.dart';

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
class LocalViewerServer implements ViewerServer {
  HttpServer? _server;
  int _tokenSeed = 0;
  final Map<String, _DicomObjectSource> _tokenToSource =
      <String, _DicomObjectSource>{};
  final Map<String, Uint8List> _assetCache = <String, Uint8List>{};
  final AppLogger _log = AppLogger.instance;
  static const String _tag = 'ViewerServer';

  Future<void> ensureStarted() async {
    if (_server != null) {
      return;
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _log.info(_tag, 'Server started on port ${_server!.port}');
    unawaited(_server!.forEach(_handleRequest));
  }

  @override
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
          } catch (e, st) {
            _log.warn(_tag, 'Skipped problematic instance at index $i', e, st);
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
      for (final header in source.remoteHeaders.entries) {
        upstreamRequest.headers.set(header.key, header.value);
      }
      if (!source.remoteHeaders.containsKey('Accept')) {
        upstreamRequest.headers.set(
          HttpHeaders.acceptHeader,
          'application/dicom',
        );
      }

      final upstreamResponse = await upstreamRequest.close();
      if (upstreamResponse.statusCode < 200 ||
          upstreamResponse.statusCode >= 300) {
        _log.warn(_tag, 'Remote WADO failed (${upstreamResponse.statusCode}) for $remoteUri');
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

      // Check if the response is multipart (WADO-RS)
      final contentType = upstreamResponse.headers.contentType;
      final isMultipart = contentType?.primaryType == 'multipart';

      if (isMultipart) {
        // For multipart/related responses, collect all bytes and extract
        // the first DICOM part.
        final bodyBytes = await upstreamResponse.fold<List<int>>(
          <int>[],
          (previous, element) {
            previous.addAll(element);
            return previous;
          },
        );

        final dicomBytes = _extractDicomFromMultipart(
          bodyBytes,
          contentType.toString(),
        );

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'dicom')
          ..headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
        _applyNoCacheHeaders(request.response);
        request.response.add(dicomBytes);
        await request.response.close();
      } else {
        // Single-part response — stream through directly.
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('application', 'dicom')
          ..headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
        _applyNoCacheHeaders(request.response);
        await request.response.addStream(upstreamResponse);
        await request.response.close();
      }
    } catch (e, st) {
      _log.error(_tag, 'Remote DICOM fetch error for ${source.remoteUri}', e, st);
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

  /// Extracts the first DICOM part from a multipart/related response body.
  List<int> _extractDicomFromMultipart(
    List<int> bodyBytes,
    String contentTypeHeader,
  ) {
    // Parse the boundary from Content-Type
    final boundaryMatch = RegExp(
      r'boundary="?([^";,\s]+)"?',
      caseSensitive: false,
    ).firstMatch(contentTypeHeader);
    if (boundaryMatch == null) {
      // No boundary found — return entire body as-is (best effort)
      return bodyBytes;
    }
    final boundary = '--${boundaryMatch.group(1)!}';
    final boundaryBytes = utf8.encode(boundary);

    // Find the first part between the first two boundary markers
    final bodyString = bodyBytes;
    int firstBoundaryEnd = _indexOfBytes(bodyString, boundaryBytes, 0);
    if (firstBoundaryEnd < 0) {
      return bodyBytes;
    }
    // Skip past the boundary and the CRLF after it
    firstBoundaryEnd += boundaryBytes.length;
    while (firstBoundaryEnd < bodyString.length &&
        (bodyString[firstBoundaryEnd] == 0x0D ||
            bodyString[firstBoundaryEnd] == 0x0A)) {
      firstBoundaryEnd++;
    }

    // Find the end of the part (next boundary)
    int secondBoundary = _indexOfBytes(bodyString, boundaryBytes, firstBoundaryEnd);
    if (secondBoundary < 0) {
      secondBoundary = bodyString.length;
    }

    // The part contains headers then \r\n\r\n then body
    final partBytes = bodyString.sublist(firstBoundaryEnd, secondBoundary);
    final headerEndIndex = _indexOfBytes(partBytes, [0x0D, 0x0A, 0x0D, 0x0A], 0);
    if (headerEndIndex < 0) {
      // No header separator found — could be just the body
      return partBytes;
    }

    // Strip trailing CRLF before the next boundary
    int end = partBytes.length;
    while (end > headerEndIndex + 4 &&
        (partBytes[end - 1] == 0x0D || partBytes[end - 1] == 0x0A)) {
      end--;
    }

    return partBytes.sublist(headerEndIndex + 4, end);
  }

  int _indexOfBytes(List<int> haystack, List<int> needle, int start) {
    for (var i = start; i <= haystack.length - needle.length; i++) {
      var found = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          found = false;
          break;
        }
      }
      if (found) {
        return i;
      }
    }
    return -1;
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
    _log.error(_tag, 'Internal server error on ${request.uri.path}', error, stackTrace);
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
