/// Barrel export for all viewer workspace widgets.
///
/// Each widget lives in its own file for maintainability:
///   viewer_toolbar.dart      – Tool selection bar
///   study_series_rail.dart   – Study list + series cards sidebar
///   series_card.dart         – Individual series card with thumbnail
///   metadata_panel.dart      – DICOM tag inspector
///   viewer_overlay_hud.dart  – Patient/viewport overlay
///   viewer_empty_state.dart  – Placeholder when no session is active
library;

export 'metadata_panel.dart';
export 'series_card.dart';
export 'study_series_rail.dart';
export 'viewer_empty_state.dart';
export 'viewer_grid.dart';
export 'viewer_overlay_hud.dart';
export 'viewer_toolbar.dart';

