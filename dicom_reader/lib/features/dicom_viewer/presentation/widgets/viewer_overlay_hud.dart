import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dicom_formatters.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../application/dicom_viewer_state.dart';

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
