import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../application/models/viewer_study_session.dart';
import '../../domain/entities/viewer_models.dart';

class CornerstoneViewerWidget extends StatefulWidget {
  const CornerstoneViewerWidget({
    super.key,
    required this.viewerUrl,
    required this.onViewportChanged,
    required this.onStatusChanged,
    this.onFatalError,
    this.onSeriesThumbnailGenerated,
  });

  final String viewerUrl;
  final ValueChanged<ViewportOverlayState> onViewportChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String>? onFatalError;
  final void Function(String seriesInstanceUid, String dataUrl)?
  onSeriesThumbnailGenerated;

  @override
  State<CornerstoneViewerWidget> createState() =>
      CornerstoneViewerWidgetState();
}

class CornerstoneViewerWidgetState extends State<CornerstoneViewerWidget> {
  InAppWebViewController? _webViewController;
  ViewerSeriesPayload? _pendingSeries;
  ViewerSeriesPayload? _activeSeries;
  List<String> _activeImageIds = <String>[];
  ViewerTool? _pendingTool;
  List<ViewerSeriesPayload>? _pendingThumbnailPayloads;
  bool _pageLoaded = false;
  bool _viewerReady = false;
  bool _showLoader = true;
  bool _recoveringFromLoadError = false;
  int _loadRecoveryAttempts = 0;
  Timer? _bootTimer;

  static const Duration _bootTimeout = Duration(seconds: 15);
  static const int _maxLoadRecoveryAttempts = 128;

  @override
  void dispose() {
    _bootTimer?.cancel();
    super.dispose();
  }

  Future<void> loadSeries(ViewerSeriesPayload payload) async {
    if (!_viewerReady) {
      _pendingSeries = payload;
      return;
    }

    if (!mounted) {
      return;
    }

    _activeSeries = payload;
    _activeImageIds = List<String>.from(payload.imageIds);
    _loadRecoveryAttempts = 0;
    _recoveringFromLoadError = false;

    await _sendSeriesToViewer(_activeImageIds);
  }

  Future<void> setTool(ViewerTool tool) async {
    if (!_viewerReady) {
      _pendingTool = tool;
      return;
    }

    await _evaluate(
      "window.cornerstoneViewer && window.cornerstoneViewer.setTool('${tool.name}');",
    );
  }

  Future<void> resetViewport() async {
    if (!_viewerReady) {
      return;
    }

    await _evaluate(
      'window.cornerstoneViewer && window.cornerstoneViewer.resetViewport();',
    );
  }

  Future<void> generateSeriesThumbnails(
    List<ViewerSeriesPayload> payloads,
  ) async {
    if (payloads.isEmpty) {
      return;
    }

    if (!_viewerReady) {
      _pendingThumbnailPayloads = payloads;
      return;
    }

    final requests = payloads
        .where((payload) => payload.imageIds.isNotEmpty)
        .map(
          (payload) => <String, String>{
            'seriesInstanceUid': payload.seriesInstanceUid,
            'imageId': payload.imageIds.first,
          },
        )
        .toList();

    if (requests.isEmpty) {
      return;
    }

    await _evaluate(
      'window.cornerstoneViewer && window.cornerstoneViewer.generateSeriesThumbnails(${jsonEncode(requests)});',
    );
  }

  void _reportFatal(String message) {
    if (!mounted) {
      return;
    }
    widget.onFatalError?.call(message);
  }

  Future<void> _evaluate(String source) async {
    final controller = _webViewController;
    if (!_pageLoaded || controller == null) {
      return;
    }

    try {
      await controller.evaluateJavascript(source: source);
    } catch (error, stackTrace) {
      debugPrint('Viewer evaluateJavascript error: $error\n$stackTrace');
      if (!mounted) {
        return;
      }

      widget.onStatusChanged('Viewer script error');
      _reportFatal('Viewer script error. Please open the study again.');
    }
  }

  Future<void> _sendSeriesToViewer(List<String> imageIds) async {
    final activeSeries = _activeSeries;
    if (activeSeries == null || imageIds.isEmpty) {
      return;
    }

    final payload = ViewerSeriesPayload(
      studyInstanceUid: activeSeries.studyInstanceUid,
      seriesInstanceUid: activeSeries.seriesInstanceUid,
      imageIds: imageIds,
    );

    widget.onStatusChanged('Loading ${imageIds.length} slices...');
    await _evaluate(
      'window.cornerstoneViewer && window.cornerstoneViewer.loadSeries(${jsonEncode(payload.toJson())});',
    );
  }

  String? _extractFailedImageId(String message) {
    final match = RegExp(r'Image load failed:\s*([^\s]+)').firstMatch(message);
    return match?.group(1);
  }

  bool _isCsImageUndefinedMessage(String lowerMessage) {
    return lowerMessage.contains('windowcenter') &&
        lowerMessage.contains('csimage') &&
        lowerMessage.contains('undefined');
  }

  bool _dropUnreadableSlice(String? failedImageId) {
    if (_activeImageIds.length <= 1) {
      return false;
    }

    if (failedImageId != null && failedImageId.isNotEmpty) {
      final removed = _activeImageIds.remove(failedImageId);
      if (removed) {
        return true;
      }
    }

    _activeImageIds.removeAt(0);
    return true;
  }

  bool _attemptRecoverFromLoadError(String message) {
    if (_activeSeries == null || _activeImageIds.isEmpty) {
      return false;
    }
    if (_recoveringFromLoadError) {
      return true;
    }
    if (_loadRecoveryAttempts >= _maxLoadRecoveryAttempts) {
      return false;
    }

    final lowerMessage = message.toLowerCase();
    final failedImageId = _extractFailedImageId(message);
    final isImageLoadFailure = lowerMessage.contains('image load failed:');
    final isCsImageUndefined = _isCsImageUndefinedMessage(lowerMessage);

    if (!isImageLoadFailure && !isCsImageUndefined) {
      return false;
    }
    if (!_dropUnreadableSlice(failedImageId)) {
      return false;
    }

    _recoveringFromLoadError = true;
    _loadRecoveryAttempts += 1;

    widget.onStatusChanged(
      'Skipped unreadable slice and retrying (${_activeImageIds.length} slices left)...',
    );

    unawaited(
      _sendSeriesToViewer(List<String>.from(_activeImageIds)).whenComplete(() {
        _recoveringFromLoadError = false;
      }),
    );

    return true;
  }

  void _startBootTimeout() {
    _bootTimer?.cancel();
    _bootTimer = Timer(_bootTimeout, () {
      if (!mounted || _viewerReady) {
        return;
      }

      widget.onStatusChanged('Viewer startup timed out');
      _reportFatal(
        'Viewer startup timed out. Please reopen the study or restart the app.',
      );
    });
  }

  Future<void> _flushPendingActions() async {
    final pendingTool = _pendingTool;
    final pendingSeries = _pendingSeries;
    final pendingThumbnails = _pendingThumbnailPayloads;

    _pendingTool = null;
    _pendingSeries = null;
    _pendingThumbnailPayloads = null;

    if (pendingTool != null) {
      await setTool(pendingTool);
    }

    if (pendingSeries != null) {
      await loadSeries(pendingSeries);
    }

    if (pendingThumbnails != null && pendingThumbnails.isNotEmpty) {
      await generateSeriesThumbnails(pendingThumbnails);
    }
  }

  void _handleViewerEvent(List<dynamic> args) {
    if (args.isEmpty || args.first is! Map) {
      return;
    }

    final event = Map<String, dynamic>.from(args.first as Map);
    final type = event['type'] as String? ?? '';
    final payload = event['payload'];

    switch (type) {
      case 'ready':
        _viewerReady = true;
        _bootTimer?.cancel();
        widget.onStatusChanged('Cornerstone ready');
        unawaited(_flushPendingActions());
        return;

      case 'status':
        widget.onStatusChanged(payload is String ? payload : 'Viewer ready');
        return;

      case 'viewport':
        if (payload is! Map) {
          return;
        }

        final raw = Map<String, dynamic>.from(payload);
        widget.onViewportChanged(
          ViewportOverlayState(
            zoom: (raw['zoom'] as num?)?.toDouble() ?? 1,
            windowWidth: (raw['windowWidth'] as num?)?.toDouble(),
            windowCenter: (raw['windowCenter'] as num?)?.toDouble(),
            currentImageIndex: (raw['currentImageIndex'] as num?)?.toInt() ?? 0,
            totalImages: (raw['totalImages'] as num?)?.toInt() ?? 0,
            isReady: raw['isReady'] as bool? ?? true,
            statusMessage: raw['statusMessage'] as String?,
          ),
        );
        return;

      case 'thumbnail':
        if (payload is! Map) {
          return;
        }

        final raw = Map<String, dynamic>.from(payload);
        final seriesInstanceUid = raw['seriesInstanceUid'] as String?;
        final dataUrl = raw['dataUrl'] as String?;

        if (seriesInstanceUid == null || seriesInstanceUid.isEmpty) {
          return;
        }
        if (dataUrl == null || dataUrl.isEmpty) {
          return;
        }

        widget.onSeriesThumbnailGenerated?.call(seriesInstanceUid, dataUrl);
        return;

      case 'imageLoadFailed':
        widget.onStatusChanged('Skipped unreadable slice in series');
        return;

      case 'error':
        final message = payload is String ? payload : 'Viewer error';
        if (_attemptRecoverFromLoadError(message)) {
          return;
        }
        widget.onStatusChanged(message);
        _reportFatal(message);
        return;

      default:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.viewerUrl.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _reportFatal('Viewer URL is not available. Please open a study again.');
      });

      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Viewer URL is not available. Please open a study again.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(url)),
            initialSettings: InAppWebViewSettings(
              transparentBackground: true,
              isInspectable: true,
              useShouldOverrideUrlLoading: false,
              disableDefaultErrorPage: true,
              cacheEnabled: false,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
              unawaited(InAppWebViewController.clearAllCache());

              controller.addJavaScriptHandler(
                handlerName: 'viewerEvent',
                callback: (args) {
                  if (!mounted) {
                    return;
                  }

                  try {
                    _handleViewerEvent(args);
                  } catch (error, stackTrace) {
                    debugPrint(
                      'Viewer event callback error: $error\n$stackTrace',
                    );
                    if (!mounted) {
                      return;
                    }
                    widget.onStatusChanged('Viewer event error');
                    _reportFatal(
                      'Viewer event error. Please reopen the study.',
                    );
                  }
                },
              );
            },
            onConsoleMessage: (controller, message) {
              final text = message.message;
              if (text.isEmpty) {
                return;
              }

              debugPrint('Viewer console: ${message.messageLevel} $text');

              final lower = text.toLowerCase();
              if (lower.contains('error') || lower.contains('failed')) {
                widget.onStatusChanged(text);
              }
            },
            onLoadStart: (controller, uri) {
              _pageLoaded = false;
              _viewerReady = false;
              _activeSeries = null;
              _activeImageIds = <String>[];
              _loadRecoveryAttempts = 0;
              _recoveringFromLoadError = false;

              if (mounted) {
                setState(() => _showLoader = true);
              }
              _startBootTimeout();
            },
            onLoadStop: (controller, uri) async {
              _pageLoaded = true;
              if (mounted) {
                setState(() => _showLoader = false);
              }

              widget.onStatusChanged('Initializing Cornerstone...');
              await _evaluate(
                'window.cornerstoneViewer && window.cornerstoneViewer.initializeViewer();',
              );
            },
            onReceivedError: (controller, request, error) {
              final message = 'Could not load viewer: ${error.description}';
              widget.onStatusChanged(message);
              _reportFatal(message);
            },
          ),
        ),
        if (_showLoader) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
