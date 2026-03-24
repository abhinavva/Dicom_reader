import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dicom_formatters.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../application/dicom_viewer_state.dart';
import '../../domain/entities/dicom_models.dart';
import '../../domain/entities/viewer_models.dart';

extension ViewerToolPresentation on ViewerTool {
  String get label => switch (this) {
    ViewerTool.windowLevel => 'Window',
    ViewerTool.zoom => 'Zoom',
    ViewerTool.pan => 'Pan',
    ViewerTool.stackScroll => 'Scroll',
    ViewerTool.crosshair => 'Crosshair',
    ViewerTool.length => 'Length',
    ViewerTool.angle => 'Angle',
  };

  IconData get icon => switch (this) {
    ViewerTool.windowLevel => Icons.tune_rounded,
    ViewerTool.zoom => Icons.zoom_in_map_rounded,
    ViewerTool.pan => Icons.pan_tool_alt_rounded,
    ViewerTool.stackScroll => Icons.unfold_more_rounded,
    ViewerTool.crosshair => Icons.center_focus_strong_rounded,
    ViewerTool.length => Icons.straighten_rounded,
    ViewerTool.angle => Icons.change_history_rounded,
  };
}

class ViewerToolbar extends StatelessWidget {
  const ViewerToolbar({
    super.key,
    required this.activeTool,
    required this.onToolSelected,
    required this.onReset,
  });

  final ViewerTool activeTool;
  final ValueChanged<ViewerTool> onToolSelected;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderRadius: BorderRadius.circular(26),
      color: AppTheme.glassToolbar,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tool in ViewerTool.values)
            _ToolbarButton(
              icon: tool.icon,
              label: tool.label,
              isActive: activeTool == tool,
              onTap: () => onToolSelected(tool),
            ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onReset,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class StudySeriesRail extends StatelessWidget {
  const StudySeriesRail({
    super.key,
    required this.state,
    required this.onStudySelected,
    required this.onSeriesSelected,
  });

  final DicomViewerState state;
  final ValueChanged<String> onStudySelected;
  final ValueChanged<String> onSeriesSelected;

  @override
  Widget build(BuildContext context) {
    final studies = state.bundle?.studies ?? const <DicomStudy>[];

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      color: AppTheme.glassRail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dataset_linked_rounded, color: AppTheme.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Study / Series',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: studies.isEmpty
                ? const Center(child: Text('No study loaded'))
                : ListView.separated(
                    itemCount: studies.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final study = studies[index];
                      final selectedStudy =
                          state.selectedStudy?.studyInstanceUid ==
                          study.studyInstanceUid;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () =>
                                onStudySelected(study.studyInstanceUid),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: selectedStudy
                                    ? AppTheme.onSurface.withValues(alpha: 0.1)
                                    : AppTheme.onSurface.withValues(
                                        alpha: 0.04,
                                      ),
                                border: Border.all(
                                  color: selectedStudy
                                      ? AppTheme.accent.withValues(alpha: 0.5)
                                      : AppTheme.onSurface.withValues(
                                          alpha: 0.08,
                                        ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    formatDicomName(study.patientName),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    study.studyDescription.isEmpty
                                        ? 'No study description'
                                        : study.studyDescription,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${formatDicomDate(study.studyDate)}  |  ${study.series.length} series',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final series in study.series)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SeriesCard(
                                series: series,
                                thumbnailBytes: state
                                    .seriesThumbnails[series.seriesInstanceUid],
                                isSelected:
                                    state.selectedSeries?.seriesInstanceUid ==
                                    series.seriesInstanceUid,
                                onTap: () =>
                                    onSeriesSelected(series.seriesInstanceUid),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class MetadataPanel extends StatelessWidget {
  const MetadataPanel({super.key, required this.state});

  final DicomViewerState state;

  @override
  Widget build(BuildContext context) {
    final study = state.selectedStudy;
    final series = state.selectedSeries;
    final instance = state.selectedInstance;

    return GlassPanel(
      padding: const EdgeInsets.all(18),
      color: AppTheme.glassMetadata,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_rounded, color: AppTheme.highlight),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Metadata',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (study != null) ...[
            _MetadataSummaryTile(
              label: 'Patient',
              value: formatDicomName(study.patientName),
            ),
            _MetadataSummaryTile(
              label: 'Patient ID',
              value: study.patientId.isEmpty
                  ? 'Not available'
                  : study.patientId,
            ),
            _MetadataSummaryTile(
              label: 'Study',
              value: study.studyDescription.isEmpty
                  ? 'Not available'
                  : study.studyDescription,
            ),
            _MetadataSummaryTile(
              label: 'Series',
              value: series?.description ?? 'No series selected',
            ),
            const SizedBox(height: 18),
          ],
          Expanded(
            child: instance == null
                ? const Center(
                    child: Text('Select a series to inspect metadata'),
                  )
                : ListView.separated(
                    itemCount: instance.metadata.length,
                    separatorBuilder: (context, index) => Divider(
                      color: AppTheme.onSurface.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (context, index) {
                      final entry = instance.metadata[index];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 112,
                            child: Text(
                              entry.tag,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: AppTheme.onSurface.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.label,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppTheme.onSurface.withValues(
                                          alpha: 0.85,
                                        ),
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(entry.value),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ViewerOverlayHud extends StatelessWidget {
  const ViewerOverlayHud({super.key, required this.state});

  final DicomViewerState state;

  @override
  Widget build(BuildContext context) {
    final study = state.selectedStudy;
    final series = state.selectedSeries;
    final viewport = state.viewportState;

    if (study == null || series == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 18,
            child: _OverlayBlock(
              alignment: CrossAxisAlignment.start,
              lines: [
                formatDicomName(study.patientName),
                study.patientId.isEmpty
                    ? 'ID unavailable'
                    : 'ID ${study.patientId}',
              ],
            ),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: _OverlayBlock(
              alignment: CrossAxisAlignment.end,
              lines: [formatDicomDate(study.studyDate), series.modality],
            ),
          ),
          Positioned(
            left: 18,
            bottom: 18,
            child: _OverlayBlock(
              alignment: CrossAxisAlignment.start,
              lines: [
                series.description.isEmpty
                    ? 'Unnamed Series'
                    : series.description,
              ],
            ),
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: _OverlayBlock(
              alignment: CrossAxisAlignment.end,
              lines: [
                formatViewportZoom(viewport.zoom),
                formatWindowLevel(viewport.windowWidth, viewport.windowCenter),
                viewport.totalImages == 0
                    ? 'Slice --'
                    : 'Slice ${viewport.currentImageIndex + 1}/${viewport.totalImages}',
              ],
            ),
          ),
          if (viewport.statusMessage case final message?)
            Positioned(
              left: 18,
              right: 18,
              bottom: 86,
              child: Center(
                child: GlassPanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  color: AppTheme.glassHud,
                  child: Text(message),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ViewerEmptyState extends StatelessWidget {
  const ViewerEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: GlassPanel(
          padding: const EdgeInsets.all(28),
          color: AppTheme.glassEmpty,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accent.withValues(alpha: 0.9),
                      AppTheme.highlight.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.monitor_heart_rounded,
                  size: 42,
                  color: AppTheme.background,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'No active viewer session',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Open a study from the worklist or use the top-right icons to load local files/folders.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeriesCard extends StatefulWidget {
  const _SeriesCard({
    required this.series,
    required this.thumbnailBytes,
    required this.isSelected,
    required this.onTap,
  });

  final DicomSeries series;
  final Uint8List? thumbnailBytes;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<_SeriesCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.01 : 1,
        duration: const Duration(milliseconds: 180),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: widget.isSelected
                  ? AppTheme.accent.withValues(alpha: 0.14)
                  : AppTheme.onSurface.withValues(
                      alpha: _hovered ? 0.08 : 0.04,
                    ),
              border: Border.all(
                color: widget.isSelected
                    ? AppTheme.accent.withValues(alpha: 0.55)
                    : AppTheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                _SeriesThumbnail(
                  bytes: widget.thumbnailBytes,
                  modality: widget.series.modality,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.series.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        compactFileCount(widget.series.instances.length),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.onSurface.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _SeriesChip(label: widget.series.modality),
                          if (widget.series.leadInstance.rows != null &&
                              widget.series.leadInstance.columns != null)
                            _SeriesChip(
                              label:
                                  '${widget.series.leadInstance.columns} x ${widget.series.leadInstance.rows}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesThumbnail extends StatelessWidget {
  const _SeriesThumbnail({required this.bytes, required this.modality});

  final Uint8List? bytes;
  final String modality;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.onSurface.withValues(alpha: 0.1),
            AppTheme.onSurface.withValues(alpha: 0.03),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null && bytes!.isNotEmpty
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      modality,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ],
            )
          : Stack(
              children: [
                Center(
                  child: Text(
                    modality,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (var index = 0; index < 5; index++)
                  Positioned(
                    left: 12 + (index * 9),
                    bottom: 12,
                    child: Container(
                      width: 4,
                      height: 16 + (index * 6),
                      decoration: BoxDecoration(
                        color: AppTheme.highlight.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: isActive
            ? AppTheme.accent.withValues(alpha: 0.2)
            : AppTheme.onSurface.withValues(alpha: 0.05),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataSummaryTile extends StatelessWidget {
  const _MetadataSummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppTheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlayBlock extends StatelessWidget {
  const _OverlayBlock({required this.lines, required this.alignment});

  final List<String> lines;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          for (final line in lines)
            Text(
              line,
              textAlign: alignment == CrossAxisAlignment.end
                  ? TextAlign.end
                  : TextAlign.start,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.onSurface,
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }
}

class _SeriesChip extends StatelessWidget {
  const _SeriesChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppTheme.onSurface.withValues(alpha: 0.06),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
