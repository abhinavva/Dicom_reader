import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dicom_formatters.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../application/dicom_viewer_state.dart';
import '../../domain/entities/dicom_models.dart';
import 'series_card.dart';

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
                                    '${formatDicomDate(study.studyDate)}  |  ${study.series.where((s) => s.isImageModality).length} series',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final series in study.series.where((s) => s.isImageModality))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: SeriesCard(
                                series: series,
                                thumbnailBytes: state
                                    .seriesThumbnails[series.seriesInstanceUid],
                                isSelected:
                                    state.selectedSeries?.seriesInstanceUid ==
                                    series.seriesInstanceUid,
                                isLoading: state.viewerSession != null &&
                                    !state.seriesThumbnails.containsKey(
                                      series.seriesInstanceUid,
                                    ),
                                loadProgress: state.seriesLoadProgress[series.seriesInstanceUid],
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
