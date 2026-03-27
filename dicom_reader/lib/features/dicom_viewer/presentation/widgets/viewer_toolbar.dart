import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../domain/entities/viewer_models.dart';

// ── Presentation helpers ────────────────────────────────────────────

extension ViewerToolPresentation on ViewerTool {
  String get label => switch (this) {
    // Navigation
    ViewerTool.windowLevel => 'W/L',
    ViewerTool.zoom => 'Zoom',
    ViewerTool.pan => 'Pan',
    ViewerTool.stackScroll => 'Scroll',
    ViewerTool.magnify => 'Magnify',
    ViewerTool.planarRotate => 'Rotate',
    // Measurement
    ViewerTool.length => 'Length',
    ViewerTool.angle => 'Angle',
    ViewerTool.cobbAngle => 'Cobb',
    ViewerTool.bidirectional => 'Bidir',
    ViewerTool.probe => 'Probe',
    // ROI
    ViewerTool.ellipticalRoi => 'Ellipse',
    ViewerTool.rectangleRoi => 'Rect',
    ViewerTool.circleRoi => 'Circle',
    ViewerTool.freehandRoi => 'Freehand',
    // Annotation
    ViewerTool.arrowAnnotate => 'Arrow',
    ViewerTool.eraser => 'Eraser',
    // Pseudo
    ViewerTool.crosshair => 'Crosshair',
  };

  IconData get icon => switch (this) {
    // Navigation
    ViewerTool.windowLevel => Icons.tune_rounded,
    ViewerTool.zoom => Icons.zoom_in_map_rounded,
    ViewerTool.pan => Icons.pan_tool_alt_rounded,
    ViewerTool.stackScroll => Icons.unfold_more_rounded,
    ViewerTool.magnify => Icons.search_rounded,
    ViewerTool.planarRotate => Icons.rotate_right_rounded,
    // Measurement
    ViewerTool.length => Icons.straighten_rounded,
    ViewerTool.angle => Icons.change_history_rounded,
    ViewerTool.cobbAngle => Icons.architecture_rounded,
    ViewerTool.bidirectional => Icons.swap_horiz_rounded,
    ViewerTool.probe => Icons.pin_drop_rounded,
    // ROI
    ViewerTool.ellipticalRoi => Icons.circle_outlined,
    ViewerTool.rectangleRoi => Icons.crop_square_rounded,
    ViewerTool.circleRoi => Icons.radio_button_unchecked_rounded,
    ViewerTool.freehandRoi => Icons.gesture_rounded,
    // Annotation
    ViewerTool.arrowAnnotate => Icons.arrow_right_alt_rounded,
    ViewerTool.eraser => Icons.auto_fix_off_rounded,
    // Pseudo
    ViewerTool.crosshair => Icons.center_focus_strong_rounded,
  };

}

// ── Toolbar widget ──────────────────────────────────────────────────

class ViewerToolbar extends StatelessWidget {
  const ViewerToolbar({
    super.key,
    required this.activeTool,
    required this.onToolSelected,
    required this.onReset,
    required this.onClearAnnotations,
    this.totalImages = 0,
    this.mprSupported = false,
    this.mprEnabled = false,
    this.onMprToggle,
    this.viewerLayout = ViewerLayout.single,
    this.onLayoutChanged,
  });

  final ViewerTool activeTool;
  final ValueChanged<ViewerTool> onToolSelected;
  final VoidCallback onReset;
  final VoidCallback onClearAnnotations;

  /// Number of images in the current series — used to disable tools
  /// that only make sense for multi-frame stacks.
  final int totalImages;

  /// Whether the current series supports MPR (volumetric modality + enough slices).
  final bool mprSupported;

  /// Whether MPR mode is currently active.
  final bool mprEnabled;

  /// Toggle MPR on/off.
  final ValueChanged<bool>? onMprToggle;

  /// Current viewport grid layout.
  final ViewerLayout viewerLayout;

  /// Called when the user picks a new layout.
  final ValueChanged<ViewerLayout>? onLayoutChanged;

  /// Ordered list of tools shown per group.
  static const List<ViewerTool> _navigationTools = [
    ViewerTool.windowLevel,
    ViewerTool.zoom,
    ViewerTool.pan,
    ViewerTool.stackScroll,
    ViewerTool.magnify,
    ViewerTool.planarRotate,
    ViewerTool.crosshair,
  ];

  static const List<ViewerTool> _measurementTools = [
    ViewerTool.length,
    ViewerTool.angle,
    ViewerTool.cobbAngle,
    ViewerTool.bidirectional,
    ViewerTool.probe,
  ];

  static const List<ViewerTool> _roiTools = [
    ViewerTool.ellipticalRoi,
    ViewerTool.rectangleRoi,
    ViewerTool.circleRoi,
    ViewerTool.freehandRoi,
  ];

  static const List<ViewerTool> _annotationTools = [
    ViewerTool.arrowAnnotate,
    ViewerTool.eraser,
  ];

  bool _isEnabled(ViewerTool tool) {
    if (tool.requiresMultiFrame && totalImages <= 1) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      borderRadius: BorderRadius.circular(26),
      color: AppTheme.glassToolbar,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IgnorePointer(
              ignoring: mprEnabled,
              child: Opacity(
                opacity: mprEnabled ? 0.35 : 1.0,
                child: _LayoutSelector(
                  current: viewerLayout,
                  onChanged: onLayoutChanged,
                ),
              ),
            ),
            _separator(),
            ..._buildGroup(_navigationTools),
            _separator(),
            ..._buildGroup(_measurementTools),
            _separator(),
            ..._buildGroup(_roiTools),
            _separator(),
            ..._buildGroup(_annotationTools),
            if (mprSupported) ...[
              _separator(),
              ..._buildMprControls(),
            ],
            _separator(),
            _ActionButton(
              icon: Icons.delete_sweep_rounded,
              label: 'Clear',
              onTap: onClearAnnotations,
            ),
            const SizedBox(width: 4),
            _ActionButton(
              icon: Icons.replay_rounded,
              label: 'Reset',
              onTap: onReset,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMprControls() {
    return [
      // MPR toggle
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: _ToolbarButton(
          icon: Icons.view_in_ar_rounded,
          label: mprEnabled ? 'Exit MPR' : 'MPR',
          isActive: mprEnabled,
          enabled: true,
          onTap: () => onMprToggle?.call(!mprEnabled),
        ),
      ),
    ];
  }

  List<Widget> _buildGroup(List<ViewerTool> tools) {
    return [
      for (final tool in tools)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: _ToolbarButton(
            icon: tool.icon,
            label: tool.label,
            isActive: activeTool == tool,
            enabled: _isEnabled(tool),
            onTap: () => onToolSelected(tool),
          ),
        ),
    ];
  }

  static Widget _separator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        height: 28,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: AppTheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

// ── Tool button ─────────────────────────────────────────────────────

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveOpacity = enabled ? 1.0 : 0.35;

    return Opacity(
      opacity: effectiveOpacity,
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 400),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isActive
                ? AppTheme.accent.withValues(alpha: 0.2)
                : AppTheme.onSurface.withValues(alpha: 0.05),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Icon(icon, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Action button (Reset / Clear) ───────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppTheme.onSurface.withValues(alpha: 0.05),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Layout selector ─────────────────────────────────────────────────

class _LayoutSelector extends StatelessWidget {
  const _LayoutSelector({
    required this.current,
    this.onChanged,
  });

  final ViewerLayout current;
  final ValueChanged<ViewerLayout>? onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ViewerLayout>(
      tooltip: 'Viewport layout',
      onSelected: onChanged,
      initialValue: current,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppTheme.surface,
      itemBuilder: (_) => [
        for (final layout in ViewerLayout.values)
          PopupMenuItem<ViewerLayout>(
            value: layout,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: _LayoutIcon(
                    rows: layout.rows,
                    columns: layout.columns,
                    isActive: layout == current,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  layout.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: layout == current
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Tooltip(
        message: 'Layout: ${current.label}',
        waitDuration: const Duration(milliseconds: 400),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: current != ViewerLayout.single
                ? AppTheme.accent.withValues(alpha: 0.2)
                : AppTheme.onSurface.withValues(alpha: 0.05),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: _LayoutIcon(
                  rows: current.rows,
                  columns: current.columns,
                  isActive: true,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                current.label,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints a mini grid icon representing the layout.
class _LayoutIcon extends StatelessWidget {
  const _LayoutIcon({
    required this.rows,
    required this.columns,
    this.isActive = false,
  });

  final int rows;
  final int columns;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LayoutIconPainter(
        rows: rows,
        columns: columns,
        color: isActive
            ? AppTheme.accent
            : AppTheme.onSurface.withValues(alpha: 0.4),
      ),
    );
  }
}

class _LayoutIconPainter extends CustomPainter {
  _LayoutIconPainter({
    required this.rows,
    required this.columns,
    required this.color,
  });

  final int rows;
  final int columns;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 1.5;
    final cellW = (size.width - (columns - 1) * gap) / columns;
    final cellH = (size.height - (rows - 1) * gap) / rows;
    final paint = Paint()..color = color;
    final radius = Radius.circular(cellW * 0.15);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < columns; c++) {
        final rect = RRect.fromLTRBR(
          c * (cellW + gap),
          r * (cellH + gap),
          c * (cellW + gap) + cellW,
          r * (cellH + gap) + cellH,
          radius,
        );
        canvas.drawRRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutIconPainter old) =>
      rows != old.rows || columns != old.columns || color != old.color;
}
