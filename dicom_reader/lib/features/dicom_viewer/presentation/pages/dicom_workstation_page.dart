import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/app_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/dicom_viewer_controller.dart';
import '../../application/dicom_viewer_state.dart';
import '../../application/models/viewer_study_session.dart';
import '../../application/providers/dicom_viewer_providers.dart';
import '../../domain/entities/viewer_models.dart';
import '../widgets/worklist_shell.dart';
import '../widgets/workstation_shell.dart';

class DicomWorkstationPage extends ConsumerStatefulWidget {
  const DicomWorkstationPage({super.key});

  @override
  ConsumerState<DicomWorkstationPage> createState() =>
      _DicomWorkstationPageState();
}

class _DicomWorkstationPageState extends ConsumerState<DicomWorkstationPage> {
  final GlobalKey<ViewerGridState> _gridKey = GlobalKey<ViewerGridState>();
  ViewerTool? _appliedTool;
  String? _thumbnailRequestSessionKey;
  final AppLogger _log = AppLogger.instance;
  static const String _tag = 'WorkstationPage';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dicomViewerControllerProvider.notifier).loadPublicWorklist();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dicomViewerControllerProvider);
    final controller = ref.read(dicomViewerControllerProvider.notifier);

    final isViewerScreen = state.screen == WorkstationScreen.viewer;
    if (!isViewerScreen) {
      _appliedTool = null;
      _thumbnailRequestSessionKey = null;
    }

    if (isViewerScreen && _appliedTool != state.activeTool) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _gridKey.currentState?.setToolAll(state.activeTool);
          _appliedTool = state.activeTool;
        } catch (e, st) {
          _log.error(_tag, 'setTool error', e, st);
          controller.resetToEmptyWithError(
            'Viewer tool error. Please try opening the study again.',
          );
        }
      });
    }

    final viewerSession = state.viewerSession;
    if (isViewerScreen && viewerSession != null) {
      final sessionKey =
          '${viewerSession.viewerUrl}|${viewerSession.seriesPayloads.length}';
      if (_thumbnailRequestSessionKey != sessionKey) {
        _thumbnailRequestSessionKey = sessionKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _gridKey.currentState?.generateSeriesThumbnails(
            viewerSession.seriesPayloads.values.toList(),
          );
        });
      }
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.background,
              AppTheme.gradientMid,
              AppTheme.gradientEnd,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                WorkstationTopBar(
                  showViewerBack: isViewerScreen,
                  isRefreshingWorklist: state.isWorklistLoading,
                  onBackToWorklist: controller.goToWorklist,
                  onRefreshWorklist: () =>
                      controller.loadPublicWorklist(forceRefresh: true),
                  onOpenFilesPressed: controller.pickAndLoadFiles,
                  onOpenFolderPressed: controller.pickAndLoadStudy,
                ),
                const SizedBox(height: 12),
                if (state.errorMessage case final error?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MaterialBanner(
                      backgroundColor: AppTheme.error.withValues(alpha: 0.24),
                      content: Text(error),
                      actions: [
                        TextButton(
                          onPressed: controller.clearError,
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ),
                if (state.noticeMessage case final notice?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MaterialBanner(
                      backgroundColor: AppTheme.highlight.withValues(
                        alpha: 0.14,
                      ),
                      content: Text(notice),
                      actions: const [SizedBox.shrink()],
                    ),
                  ),
                Expanded(
                  child: isViewerScreen
                      ? _ViewerWorkspace(
                          state: state,
                          controller: controller,
                          gridKey: _gridKey,
                        )
                      : DicomWebWorklistView(
                          isLoading: state.isWorklistLoading,
                          studies: state.worklistStudies,
                          errorMessage: state.worklistErrorMessage,
                          availableEndpoints: state.availableEndpoints,
                          selectedEndpoint: state.selectedEndpoint,
                          onEndpointChanged: controller.selectEndpoint,
                          hasMore: state.worklistHasMore,
                          isLoadingMore: state.isLoadingMoreWorklist,
                          onLoadMore: controller.loadMoreWorklist,
                          onRefresh: () =>
                              controller.loadPublicWorklist(forceRefresh: true),
                          onOpenStudy: controller.openWorklistStudy,
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

bool _isMprSupported(DicomViewerState state) {
  final series = state.selectedSeries;
  if (series == null) return false;
  final modality = series.modality.toUpperCase();
  return mprCapableModalities.contains(modality) &&
      series.instances.length >= mprMinSliceCount;
}

/// Builds an ordered list of series payloads for the grid — image series
/// in the order they appear in the study.
List<ViewerSeriesPayload> _orderedPayloads(DicomViewerState state) {
  final session = state.viewerSession;
  final study = state.selectedStudy;
  if (session == null || study == null) return const [];

  return study.series
      .where((s) => s.isImageModality)
      .map((s) => session.seriesPayloads[s.seriesInstanceUid])
      .whereType<ViewerSeriesPayload>()
      .toList();
}

class _ViewerWorkspace extends StatelessWidget {
  const _ViewerWorkspace({
    required this.state,
    required this.controller,
    required this.gridKey,
  });

  final DicomViewerState state;
  final DicomViewerController controller;
  final GlobalKey<ViewerGridState> gridKey;

  @override
  Widget build(BuildContext context) {
    if (state.viewerSession == null) {
      return const ViewerEmptyState();
    }

    final payloads = _orderedPayloads(state);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return _CompactWorkstation(
            state: state,
            controller: controller,
            gridKey: gridKey,
            orderedPayloads: payloads,
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 340,
              child: StudySeriesRail(
                state: state,
                onStudySelected: controller.selectStudy,
                onSeriesSelected: controller.selectSeries,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildToolbar(state, controller, gridKey),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ViewerGrid(
                            key: gridKey,
                            layout: state.viewerLayout,
                            viewerUrl: state.viewerSession!.viewerUrl,
                            orderedPayloads: payloads,
                            activeTool: state.activeTool,
                            activeSeriesUid:
                                state.selectedSeries?.seriesInstanceUid,
                            onViewportChanged: controller.updateViewport,
                            onStatusChanged: controller.setViewerStatus,
                            onFatalError: controller.resetToEmptyWithError,
                            onSeriesThumbnailGenerated:
                                controller.setSeriesThumbnailFromDataUrl,
                            onImageProgress:
                                controller.updateSeriesLoadProgress,
                            onCellTapped: (index) {
                              if (index < payloads.length) {
                                controller.selectSeries(
                                  payloads[index].seriesInstanceUid,
                                );
                              }
                            },
                          ),
                        ),
                        Positioned.fill(child: ViewerOverlayHud(state: state)),
                        if (state.isBusy)
                          Positioned.fill(
                            child: ColoredBox(
                              color: AppTheme.background.withValues(alpha: 0.6),
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(width: 360, child: MetadataPanel(state: state)),
          ],
        );
      },
    );
  }
}

Widget _buildToolbar(
  DicomViewerState state,
  DicomViewerController controller,
  GlobalKey<ViewerGridState> gridKey,
) {
  return ViewerToolbar(
    activeTool: state.activeTool,
    totalImages: state.viewportState.totalImages,
    viewerLayout: state.viewerLayout,
    onLayoutChanged: controller.setLayout,
    onToolSelected: (tool) {
      controller.setTool(tool);
      gridKey.currentState?.setToolAll(tool);
    },
    onReset: () => gridKey.currentState?.resetAll(),
    onClearAnnotations: () => gridKey.currentState?.clearAnnotationsAll(),
    mprSupported: _isMprSupported(state),
    mprEnabled: state.mprActive,
    onMprToggle: (enabled) {
      controller.toggleMpr(enabled);
      if (enabled) {
        gridKey.currentState?.enableMprOnPrimary();
      } else {
        gridKey.currentState?.disableMprOnPrimary();
      }
    },
  );
}

class _CompactWorkstation extends StatelessWidget {
  const _CompactWorkstation({
    required this.state,
    required this.controller,
    required this.gridKey,
    required this.orderedPayloads,
  });

  final DicomViewerState state;
  final DicomViewerController controller;
  final GlobalKey<ViewerGridState> gridKey;
  final List<ViewerSeriesPayload> orderedPayloads;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 260,
          child: StudySeriesRail(
            state: state,
            onStudySelected: controller.selectStudy,
            onSeriesSelected: controller.selectSeries,
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: _buildToolbar(state, controller, gridKey),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: ViewerGrid(
                  key: gridKey,
                  layout: state.viewerLayout,
                  viewerUrl: state.viewerSession!.viewerUrl,
                  orderedPayloads: orderedPayloads,
                  activeTool: state.activeTool,
                  activeSeriesUid:
                      state.selectedSeries?.seriesInstanceUid,
                  onViewportChanged: controller.updateViewport,
                  onStatusChanged: controller.setViewerStatus,
                  onFatalError: controller.resetToEmptyWithError,
                  onSeriesThumbnailGenerated:
                      controller.setSeriesThumbnailFromDataUrl,
                  onImageProgress:
                      controller.updateSeriesLoadProgress,
                  onCellTapped: (index) {
                    if (index < orderedPayloads.length) {
                      controller.selectSeries(
                        orderedPayloads[index].seriesInstanceUid,
                      );
                    }
                  },
                ),
              ),
              Positioned.fill(child: ViewerOverlayHud(state: state)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(height: 260, child: MetadataPanel(state: state)),
      ],
    );
  }
}
