/// All viewer interaction tools.
///
/// The [name] of each value matches the key used in the JS `toolNames` map
/// so it can be sent to `window.cornerstoneViewer.setTool(name)` directly.
enum ViewerTool {
  // ── Navigation ──────────────────────────────────────────
  windowLevel,
  zoom,
  pan,
  stackScroll,
  magnify,
  planarRotate,

  // ── Measurement ─────────────────────────────────────────
  length,
  angle,
  cobbAngle,
  bidirectional,
  probe,

  // ── ROI ─────────────────────────────────────────────────
  ellipticalRoi,
  rectangleRoi,
  circleRoi,
  freehandRoi,

  // ── Annotation ──────────────────────────────────────────
  arrowAnnotate,
  eraser,

  // ── Pseudo-tools (handled in Flutter / CSS) ─────────────
  crosshair,
}

/// Whether a tool requires a multi-frame stack to be useful.
extension ViewerToolCapability on ViewerTool {
  bool get requiresMultiFrame => switch (this) {
    ViewerTool.stackScroll => true,
    _ => false,
  };
}

/// MPR orientation axis.
enum MprOrientation { axial, sagittal, coronal }

/// Modalities that support MPR reconstruction (volumetric 3-D acquisitions).
const Set<String> mprCapableModalities = <String>{
  'CT', 'MR', 'PT', 'NM', 'SPECT',
};

/// Minimum number of slices required for a useful MPR reconstruction.
const int mprMinSliceCount = 10;

/// Viewport grid layout presets (rows × columns).
enum ViewerLayout {
  single(1, 1),   // 1×1
  oneByTwo(1, 2), // 1×2
  oneByThree(1, 3), // 1×3 (used for MPR)
  twoByOne(2, 1), // 2×1
  twoByTwo(2, 2), // 2×2
  twoByThree(2, 3), // 2×3
  threeByThree(3, 3); // 3×3

  const ViewerLayout(this.rows, this.columns);

  final int rows;
  final int columns;

  int get cellCount => rows * columns;

  String get label => '$rows×$columns';
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
    this.mprEnabled = false,
    this.mprOrientation,
  });

  final double zoom;
  final double? windowWidth;
  final double? windowCenter;
  final int currentImageIndex;
  final int totalImages;
  final bool isReady;
  final String? statusMessage;
  final bool mprEnabled;
  final MprOrientation? mprOrientation;

  ViewportOverlayState copyWith({
    double? zoom,
    Object? windowWidth = _keep,
    Object? windowCenter = _keep,
    int? currentImageIndex,
    int? totalImages,
    bool? isReady,
    Object? statusMessage = _keep,
    bool? mprEnabled,
    Object? mprOrientation = _keep,
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
      mprEnabled: mprEnabled ?? this.mprEnabled,
      mprOrientation: identical(mprOrientation, _keep)
          ? this.mprOrientation
          : mprOrientation as MprOrientation?,
    );
  }

  static const Object _keep = Object();
}
