import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/models/viewer_study_session.dart';
import '../../domain/entities/viewer_models.dart';
import '../cornerstone_viewer/cornerstone_viewer_widget.dart';

/// Displays a grid of [CornerstoneViewerWidget] instances according to the
/// selected [ViewerLayout].  Each cell is assigned a series from
/// [orderedPayloads] in order; cells beyond the series count stay empty.
class ViewerGrid extends StatefulWidget {
  const ViewerGrid({
    super.key,
    required this.layout,
    required this.viewerUrl,
    required this.orderedPayloads,
    required this.activeTool,
    required this.activeSeriesUid,
    required this.onViewportChanged,
    required this.onStatusChanged,
    this.onFatalError,
    this.onSeriesThumbnailGenerated,
    this.onImageProgress,
    this.onCellTapped,
  });

  final ViewerLayout layout;
  final String viewerUrl;

  /// Series payloads in display order — index 0 goes to cell 0, etc.
  final List<ViewerSeriesPayload> orderedPayloads;

  final ViewerTool activeTool;

  /// The currently-selected series UID (highlighted cell).
  final String? activeSeriesUid;

  final ValueChanged<ViewportOverlayState> onViewportChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String>? onFatalError;
  final void Function(String seriesInstanceUid, String dataUrl)?
      onSeriesThumbnailGenerated;
  final void Function(String seriesInstanceUid, int loaded, int total)?
      onImageProgress;

  /// Called when a cell is tapped — provides the series UID (or null for empty).
  final ValueChanged<int>? onCellTapped;

  @override
  State<ViewerGrid> createState() => ViewerGridState();
}

class ViewerGridState extends State<ViewerGrid> {
  /// Keys for each cell's viewer widget, indexed by cell position.
  final Map<int, GlobalKey<CornerstoneViewerWidgetState>> _viewerKeys = {};

  /// Which series UID is currently loaded in each cell.
  final Map<int, String?> _loadedSeriesPerCell = {};

  /// Track which cells have their viewer ready.
  final Set<int> _readyCells = {};

  CornerstoneViewerWidgetState? _primaryViewerState() =>
      _viewerKeys[0]?.currentState;

  /// Forward tool changes to all active viewers.
  void setToolAll(ViewerTool tool) {
    for (final entry in _viewerKeys.entries) {
      if (_readyCells.contains(entry.key)) {
        entry.value.currentState?.setTool(tool);
      }
    }
  }

  /// Forward reset to all active viewers.
  void resetAll() {
    for (final entry in _viewerKeys.entries) {
      if (_readyCells.contains(entry.key)) {
        entry.value.currentState?.resetViewport();
      }
    }
  }

  /// Forward clear annotations to all active viewers.
  void clearAnnotationsAll() {
    for (final entry in _viewerKeys.entries) {
      if (_readyCells.contains(entry.key)) {
        entry.value.currentState?.clearAnnotations();
      }
    }
  }

  /// Enable MPR on the primary (cell 0) viewer.
  void enableMprOnPrimary() {
    _primaryViewerState()?.enableMpr(MprOrientation.axial);
  }

  /// Disable MPR on the primary (cell 0) viewer.
  void disableMprOnPrimary() {
    _primaryViewerState()?.disableMpr();
  }

  /// Generate thumbnails via the primary (cell 0) viewer.
  void generateSeriesThumbnails(List<ViewerSeriesPayload> payloads) {
    _primaryViewerState()?.generateSeriesThumbnails(payloads);
  }

  GlobalKey<CornerstoneViewerWidgetState> _keyForCell(int index) {
    return _viewerKeys.putIfAbsent(
      index,
      () => GlobalKey<CornerstoneViewerWidgetState>(),
    );
  }

  @override
  void didUpdateWidget(covariant ViewerGrid oldWidget) {
    super.didUpdateWidget(oldWidget);

    final layoutChanged = widget.layout != oldWidget.layout;

    if (layoutChanged) {
      // Layout changed — viewers are rebuilt so all tracking is stale.
      _readyCells.clear();
      _loadedSeriesPerCell.clear();
      _viewerKeys.clear();
    } else {
      // Prune cells that no longer exist.
      final maxCells = widget.layout.cellCount;
      _viewerKeys.removeWhere((key, _) => key >= maxCells);
      _loadedSeriesPerCell.removeWhere((key, _) => key >= maxCells);
      _readyCells.removeWhere((cell) => cell >= maxCells);
    }

    // Load series into cells that need updating.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSeriesToCells();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSeriesToCells();
    });
  }

  void _syncSeriesToCells() {
    final payloads = widget.orderedPayloads;
    final cellCount = widget.layout.cellCount;

    for (int i = 0; i < cellCount; i++) {
      final payload = i < payloads.length ? payloads[i] : null;
      final currentUid = _loadedSeriesPerCell[i];
      final newUid = payload?.seriesInstanceUid;

      if (newUid != currentUid && _readyCells.contains(i)) {
        if (payload != null) {
          _viewerKeys[i]?.currentState?.loadSeries(payload);
        }
        _loadedSeriesPerCell[i] = newUid;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final cellCount = layout.cellCount;
    final payloads = widget.orderedPayloads;

    if (cellCount == 1) {
      // Single viewport — no grid needed.
      return _buildCell(0, payloads.isNotEmpty ? payloads[0] : null);
    }

    return Column(
      children: [
        for (int row = 0; row < layout.rows; row++)
          Expanded(
            child: Row(
              children: [
                for (int col = 0; col < layout.columns; col++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: () {
                        final index = row * layout.columns + col;
                        final payload =
                            index < payloads.length ? payloads[index] : null;
                        return _buildCell(index, payload);
                      }(),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCell(int index, ViewerSeriesPayload? payload) {
    final isActive = payload != null &&
        payload.seriesInstanceUid == widget.activeSeriesUid;

    return GestureDetector(
      onTap: () => widget.onCellTapped?.call(index),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            widget.layout.cellCount == 1 ? 28 : 8,
          ),
          border: widget.layout.cellCount > 1
              ? Border.all(
                  color: isActive
                      ? AppTheme.accent.withValues(alpha: 0.6)
                      : AppTheme.onSurface.withValues(alpha: 0.08),
                  width: isActive ? 2 : 1,
                )
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: payload != null
            ? CornerstoneViewerWidget(
                key: _keyForCell(index),
                viewerUrl: widget.viewerUrl,
                onViewportChanged: (vpState) {
                  if (isActive) widget.onViewportChanged(vpState);
                },
                onStatusChanged: (status) {
                  if (isActive || index == 0) {
                    widget.onStatusChanged(status);
                  }
                  if (status == 'Cornerstone ready') {
                    _readyCells.add(index);
                    // Load the series once the viewer is ready.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final uid = _loadedSeriesPerCell[index];
                      if (uid != payload.seriesInstanceUid) {
                        _viewerKeys[index]
                            ?.currentState
                            ?.loadSeries(payload);
                        _loadedSeriesPerCell[index] =
                            payload.seriesInstanceUid;
                      }
                    });
                  }
                },
                onFatalError: widget.onFatalError,
                onSeriesThumbnailGenerated:
                    index == 0 ? widget.onSeriesThumbnailGenerated : null,
                onImageProgress: widget.onImageProgress,
              )
            : _EmptyCell(index: index),
      ),
    );
  }
}

class _EmptyCell extends StatelessWidget {
  const _EmptyCell({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.view_compact_outlined,
              size: 32,
              color: AppTheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 8),
            Text(
              'Viewport ${index + 1}',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.onSurface.withValues(alpha: 0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
