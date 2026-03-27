import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/dicom_formatters.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../domain/entities/dicom_web_models.dart';

class WorkstationTopBar extends StatelessWidget {
  const WorkstationTopBar({
    super.key,
    required this.showViewerBack,
    required this.isRefreshingWorklist,
    required this.onBackToWorklist,
    required this.onRefreshWorklist,
    required this.onOpenFilesPressed,
    required this.onOpenFolderPressed,
  });

  final bool showViewerBack;
  final bool isRefreshingWorklist;
  final VoidCallback onBackToWorklist;
  final VoidCallback onRefreshWorklist;
  final VoidCallback onOpenFilesPressed;
  final VoidCallback onOpenFolderPressed;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: BorderRadius.circular(20),
      color: AppTheme.glassToolbar,
      child: Row(
        children: [
          if (showViewerBack) ...[
            IconButton(
              onPressed: onBackToWorklist,
              tooltip: 'Back to worklist',
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 6),
          ] else ...[
            const Icon(Icons.table_chart_rounded, color: AppTheme.highlight),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              showViewerBack ? 'Viewer Workspace' : 'Public DICOM Worklist',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton.filledTonal(
            onPressed: isRefreshingWorklist ? null : onRefreshWorklist,
            icon: isRefreshingWorklist
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Refresh worklist',
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: onOpenFilesPressed,
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Open DICOM files',
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: onOpenFolderPressed,
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: 'Open DICOM folder',
          ),
        ],
      ),
    );
  }
}

class DicomWebWorklistView extends StatelessWidget {
  const DicomWebWorklistView({
    super.key,
    required this.isLoading,
    required this.studies,
    required this.errorMessage,
    required this.onRefresh,
    required this.onOpenStudy,
    required this.availableEndpoints,
    required this.selectedEndpoint,
    required this.onEndpointChanged,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  final bool isLoading;
  final List<DicomWebWorklistStudy> studies;
  final String? errorMessage;
  final VoidCallback onRefresh;
  final ValueChanged<DicomWebWorklistStudy> onOpenStudy;
  final List<DicomWebEndpoint> availableEndpoints;
  final DicomWebEndpoint? selectedEndpoint;
  final ValueChanged<DicomWebEndpoint?> onEndpointChanged;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      color: AppTheme.glassRail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_done_rounded, color: AppTheme.highlight),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Study worklist (QIDO from public servers)',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          // const SizedBox(height: 10),
          // Text(
          //   'Open any row to fetch series/instances via QIDO and stream images via WADO into the viewer.',
          //   style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          //     color: AppTheme.onSurface.withValues(alpha: 0.78),
          //   ),
          // ),
          const SizedBox(height: 14),
          if (availableEndpoints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _EndpointSelector(
                endpoints: availableEndpoints,
                selected: selectedEndpoint,
                onChanged: onEndpointChanged,
              ),
            ),
          Expanded(
            child: switch ((isLoading, studies.isEmpty)) {
              (true, true) => const Center(child: CircularProgressIndicator()),
              (_, true) => _WorklistEmpty(
                errorMessage: errorMessage,
                onRefresh: onRefresh,
              ),
              _ => ListView.separated(
                itemCount: studies.length + (hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == studies.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: isLoadingMore
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : FilledButton.tonalIcon(
                                onPressed: onLoadMore,
                                icon: const Icon(Icons.expand_more_rounded),
                                label: const Text('Load More'),
                              ),
                      ),
                    );
                  }
                  final study = studies[index];
                  return _WorklistStudyCard(
                    study: study,
                    onOpen: () => onOpenStudy(study),
                  );
                },
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _WorklistStudyCard extends StatefulWidget {
  const _WorklistStudyCard({required this.study, required this.onOpen});

  final DicomWebWorklistStudy study;
  final VoidCallback onOpen;

  @override
  State<_WorklistStudyCard> createState() => _WorklistStudyCardState();
}

class _WorklistStudyCardState extends State<_WorklistStudyCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final study = widget.study;
    final modalities = study.modalitiesInStudy.isEmpty
        ? 'OT'
        : study.modalitiesInStudy.join(', ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppTheme.onSurface.withValues(alpha: _hovered ? 0.08 : 0.04),
          border: Border.all(
            color: _hovered
                ? AppTheme.accent.withValues(alpha: 0.45)
                : AppTheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatDicomName(study.patientName),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    study.studyDescription.isEmpty
                        ? 'No study description'
                        : study.studyDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _WorklistChip(label: study.endpoint.name),
                      _WorklistChip(label: formatDicomDate(study.studyDate)),
                      _WorklistChip(label: modalities),
                      _WorklistChip(label: '${study.seriesCount} series'),
                      if (study.patientId.isNotEmpty)
                        _WorklistChip(label: 'ID ${study.patientId}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: widget.onOpen,
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Open this study in viewer',
            ),
          ],
        ),
      ),
    );
  }
}

class _WorklistChip extends StatelessWidget {
  const _WorklistChip({required this.label});

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

class _WorklistEmpty extends StatelessWidget {
  const _WorklistEmpty({required this.errorMessage, required this.onRefresh});

  final String? errorMessage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppTheme.onSurface.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 14),
            Text(
              errorMessage ??
                  'No worklist studies available yet. Tap refresh to query public DICOMweb servers.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: onRefresh,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Refresh Worklist'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndpointSelector extends StatelessWidget {
  const _EndpointSelector({
    required this.endpoints,
    required this.selected,
    required this.onChanged,
  });

  final List<DicomWebEndpoint> endpoints;
  final DicomWebEndpoint? selected;
  final ValueChanged<DicomWebEndpoint?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.dns_rounded, size: 18, color: AppTheme.accent),
        const SizedBox(width: 8),
        Text('Server:', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selected?.id,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              filled: true,
              fillColor: AppTheme.onSurface.withValues(alpha: 0.04),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('All Servers'),
              ),
              for (final endpoint in endpoints)
                DropdownMenuItem<String>(
                  value: endpoint.id,
                  child: Text(endpoint.name),
                ),
            ],
            onChanged: (id) {
              if (id == null) {
                onChanged(null);
              } else {
                final match = endpoints.firstWhere((e) => e.id == id);
                onChanged(match);
              }
            },
          ),
        ),
      ],
    );
  }
}
