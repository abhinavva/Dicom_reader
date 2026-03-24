enum ViewerTool {
  windowLevel,
  zoom,
  pan,
  stackScroll,
  crosshair,
  length,
  angle,
}

class ViewportOverlayState {
  const ViewportOverlayState({
    this.zoom = 1,
    this.windowWidth,
    this.windowCenter,
    this.currentImageIndex = 0,
    this.totalImages = 0,
    this.isReady = false,
    this.statusMessage,
  });

  final double zoom;
  final double? windowWidth;
  final double? windowCenter;
  final int currentImageIndex;
  final int totalImages;
  final bool isReady;
  final String? statusMessage;

  ViewportOverlayState copyWith({
    double? zoom,
    Object? windowWidth = _keep,
    Object? windowCenter = _keep,
    int? currentImageIndex,
    int? totalImages,
    bool? isReady,
    Object? statusMessage = _keep,
  }) {
    return ViewportOverlayState(
      zoom: zoom ?? this.zoom,
      windowWidth: identical(windowWidth, _keep)
          ? this.windowWidth
          : windowWidth as double?,
      windowCenter: identical(windowCenter, _keep)
          ? this.windowCenter
          : windowCenter as double?,
      currentImageIndex: currentImageIndex ?? this.currentImageIndex,
      totalImages: totalImages ?? this.totalImages,
      isReady: isReady ?? this.isReady,
      statusMessage: identical(statusMessage, _keep)
          ? this.statusMessage
          : statusMessage as String?,
    );
  }

  static const Object _keep = Object();
}
