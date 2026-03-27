import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dicom_formatters.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../application/dicom_viewer_state.dart';

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
