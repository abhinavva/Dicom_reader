import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/dicom_viewer_controller.dart';
import '../../application/dicom_viewer_state.dart';
import '../../application/providers/dicom_viewer_providers.dart';
import '../../domain/entities/viewer_models.dart';
import '../cornerstone_viewer/cornerstone_viewer_widget.dart';
import '../widgets/worklist_shell.dart';
import '../widgets/workstation_shell.dart';

class DicomWorkstationPage extends ConsumerStatefulWidget {
  const DicomWorkstationPage({super.key});

  @override
  ConsumerState<DicomWorkstationPage> createState() =>
      _DicomWorkstationPageState();
}

class _DicomWorkstationPageState extends ConsumerState<DicomWorkstationPage> {
  final GlobalKey<CornerstoneViewerWidgetState> _viewerKey =
      GlobalKey<CornerstoneViewerWidgetState>();
  String? _loadedSeriesUid;
  ViewerTool? _appliedTool;
  String? _thumbnailRequestSessionKey;

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
      _loadedSeriesUid = null;
      _appliedTool = null;
      _thumbnailRequestSessionKey = null;
    }

    final selectedPayload = state.selectedSeriesPayload;

    if (isViewerScreen &&
        selectedPayload != null &&
        selectedPayload.seriesInstanceUid != _loadedSeriesUid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _viewerKey.currentState?.loadSeries(selectedPayload);
          _loadedSeriesUid = selectedPayload.seriesInstanceUid;
        } catch (e, st) {
          debugPrint('loadSeries error: $e\n$st');
          controller.resetToEmptyWithError(
            'Failed to load series. Please try opening the study again.',
          );
        }
      });
    }

    if (isViewerScreen && _appliedTool != state.activeTool) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _viewerKey.currentState?.setTool(state.activeTool);
          _appliedTool = state.activeTool;
        } catch (e, st) {
          debugPrint('setTool error: $e\n$st');
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
          _viewerKey.currentState?.generateSeriesThumbnails(
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
                          viewerKey: _viewerKey,
                        )
                      : DicomWebWorklistView(
                          isLoading: state.isWorklistLoading,
                          studies: state.worklistStudies,
                          errorMessage: state.worklistErrorMessage,
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

class _ViewerWorkspace extends StatelessWidget {
  const _ViewerWorkspace({
    required this.state,
    required this.controller,
    required this.viewerKey,
  });

  final DicomViewerState state;
  final DicomViewerController controller;
  final GlobalKey<CornerstoneViewerWidgetState> viewerKey;

  @override
  Widget build(BuildContext context) {
    if (state.viewerSession == null) {
      return const ViewerEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return _CompactWorkstation(
            state: state,
            controller: controller,
            viewerKey: viewerKey,
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
                    child: ViewerToolbar(
                      activeTool: state.activeTool,
                      onToolSelected: (tool) {
                        controller.setTool(tool);
                        viewerKey.currentState?.setTool(tool);
                      },
                      onReset: () => viewerKey.currentState?.resetViewport(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CornerstoneViewerWidget(
                            key: viewerKey,
                            viewerUrl: state.viewerSession!.viewerUrl,
                            onViewportChanged: controller.updateViewport,
                            onStatusChanged: controller.setViewerStatus,
                            onFatalError: controller.resetToEmptyWithError,
                            onSeriesThumbnailGenerated:
                                controller.setSeriesThumbnailFromDataUrl,
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

class _CompactWorkstation extends StatelessWidget {
  const _CompactWorkstation({
    required this.state,
    required this.controller,
    required this.viewerKey,
  });

  final DicomViewerState state;
  final DicomViewerController controller;
  final GlobalKey<CornerstoneViewerWidgetState> viewerKey;

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
          child: ViewerToolbar(
            activeTool: state.activeTool,
            onToolSelected: (tool) {
              controller.setTool(tool);
              viewerKey.currentState?.setTool(tool);
            },
            onReset: () => viewerKey.currentState?.resetViewport(),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: CornerstoneViewerWidget(
                  key: viewerKey,
                  viewerUrl: state.viewerSession!.viewerUrl,
                  onViewportChanged: controller.updateViewport,
                  onStatusChanged: controller.setViewerStatus,
                  onFatalError: controller.resetToEmptyWithError,
                  onSeriesThumbnailGenerated:
                      controller.setSeriesThumbnailFromDataUrl,
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
