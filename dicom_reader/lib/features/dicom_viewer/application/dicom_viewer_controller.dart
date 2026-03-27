import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_logger.dart';
import '../domain/entities/dicom_models.dart';
import '../domain/entities/dicom_web_models.dart';
import '../domain/entities/viewer_models.dart';
import '../domain/services/viewer_server.dart';
import '../domain/usecases/load_public_study_usecase.dart';
import '../domain/usecases/load_public_worklist_usecase.dart';
import '../domain/usecases/load_study_bundle_usecase.dart';
import '../domain/usecases/pick_dicom_files_usecase.dart';
import '../domain/usecases/pick_study_directory_usecase.dart';
import 'dicom_viewer_state.dart';

class DicomViewerController extends StateNotifier<DicomViewerState> {
  DicomViewerController({
    required PickStudyDirectoryUseCase pickDirectory,
    required PickDicomFilesUseCase pickFiles,
    required LoadStudyBundleUseCase loadStudyBundle,
    required LoadPublicWorklistUseCase loadPublicWorklist,
    required LoadPublicStudyUseCase loadPublicStudy,
    required ViewerServer viewerServer,
  }) : _pickDirectory = pickDirectory,
       _pickFiles = pickFiles,
       _loadStudyBundle = loadStudyBundle,
       _loadPublicWorklist = loadPublicWorklist,
       _loadPublicStudy = loadPublicStudy,
       _viewerServer = viewerServer,
       _log = AppLogger.instance,
       super(const DicomViewerState());

  final PickStudyDirectoryUseCase _pickDirectory;
  final PickDicomFilesUseCase _pickFiles;
  final LoadStudyBundleUseCase _loadStudyBundle;
  final LoadPublicWorklistUseCase _loadPublicWorklist;
  final LoadPublicStudyUseCase _loadPublicStudy;
  final ViewerServer _viewerServer;
  final AppLogger _log;

  static const String _tag = 'Controller';

  Future<void> loadPublicWorklist({bool forceRefresh = false}) async {
    if (state.isWorklistLoading) {
      return;
    }
    if (!forceRefresh && state.worklistStudies.isNotEmpty) {
      return;
    }

    if (state.availableEndpoints.isEmpty) {
      state = state.copyWith(
        availableEndpoints: _loadPublicWorklist.availableEndpoints,
      );
    }

    state = state.copyWith(
      isWorklistLoading: true,
      worklistErrorMessage: null,
      worklistOffset: 0,
      worklistHasMore: true,
    );

    _log.info(_tag, 'Loading worklist (endpoint=${state.selectedEndpoint?.id ?? "all"})');

    try {
      final pageSize = state.worklistPageSize;
      final studies = await _loadPublicWorklist(
        endpoint: state.selectedEndpoint,
        offset: 0,
        limit: pageSize,
      );
      state = state.copyWith(
        isWorklistLoading: false,
        worklistStudies: studies,
        worklistOffset: studies.length,
        worklistHasMore: studies.length >= pageSize,
        worklistErrorMessage: null,
      );
      _log.info(_tag, 'Worklist loaded: ${studies.length} studies');
    } catch (error, stack) {
      _log.error(_tag, 'Worklist load failed', error, stack);
      state = state.copyWith(
        isWorklistLoading: false,
        worklistHasMore: false,
        worklistErrorMessage: error
            .toString()
            .replaceFirst('Exception: ', '')
            .trim(),
      );
    }
  }

  Future<void> loadMoreWorklist() async {
    if (state.isWorklistLoading ||
        state.isLoadingMoreWorklist ||
        !state.worklistHasMore) {
      return;
    }

    state = state.copyWith(isLoadingMoreWorklist: true);

    _log.info(_tag, 'Loading more worklist (offset=${state.worklistOffset})');

    try {
      final pageSize = state.worklistPageSize;
      final studies = await _loadPublicWorklist(
        endpoint: state.selectedEndpoint,
        offset: state.worklistOffset,
        limit: pageSize,
      );

      final merged = <DicomWebWorklistStudy>[
        ...state.worklistStudies,
        ...studies,
      ];

      state = state.copyWith(
        isLoadingMoreWorklist: false,
        worklistStudies: merged,
        worklistOffset: merged.length,
        worklistHasMore: studies.length >= pageSize,
      );
      _log.info(_tag, 'Loaded ${studies.length} more studies (total=${merged.length})');
    } catch (error, stack) {
      _log.error(_tag, 'Load more worklist failed', error, stack);
      state = state.copyWith(
        isLoadingMoreWorklist: false,
        worklistHasMore: false,
        worklistErrorMessage: error
            .toString()
            .replaceFirst('Exception: ', '')
            .trim(),
      );
    }
  }

  void selectEndpoint(DicomWebEndpoint? endpoint) {
    if (endpoint?.id == state.selectedEndpoint?.id) {
      return;
    }
    _log.info(_tag, 'Endpoint changed to ${endpoint?.name ?? "All Servers"}');
    state = state.copyWith(
      selectedEndpoint: endpoint,
      worklistStudies: const <DicomWebWorklistStudy>[],
      worklistOffset: 0,
      worklistHasMore: true,
    );
    loadPublicWorklist(forceRefresh: true);
  }

  Future<void> openWorklistStudy(DicomWebWorklistStudy worklistStudy) async {
    _log.info(_tag, 'Opening worklist study ${worklistStudy.studyInstanceUid} from ${worklistStudy.endpoint.name}');
    await _loadBundle(
      sourceLabel:
          '${worklistStudy.endpoint.name} (${worklistStudy.studyInstanceUid})',
      multipleStudiesContext: worklistStudy.endpoint.name,
      loader: () => _loadPublicStudy(worklistStudy),
      openViewerOnSuccess: true,
    );
  }

  Future<void> pickAndLoadStudy() async {
    try {
      final directory = await _pickDirectory();
      if (directory == null || directory.isEmpty) {
        return;
      }

      await loadStudyFromDirectory(directory);
    } catch (error, stack) {
      _log.error(_tag, 'Folder picker failed', error, stack);
      state = state.copyWith(
        isBusy: false,
        errorMessage:
            'Could not open folder picker: ${error.toString().replaceFirst("Exception: ", "")}',
      );
    }
  }

  Future<void> pickAndLoadFiles() async {
    try {
      final files = await _pickFiles();
      if (files.isEmpty) {
        return;
      }

      await loadStudyFromFiles(files);
    } catch (error, stack) {
      _log.error(_tag, 'File picker failed', error, stack);
      state = state.copyWith(
        isBusy: false,
        errorMessage:
            'Could not open file picker: ${error.toString().replaceFirst("Exception: ", "")}',
      );
    }
  }

  Future<void> loadStudyFromDirectory(String directoryPath) async {
    await _loadBundle(
      sourceLabel: directoryPath,
      multipleStudiesContext: 'this folder',
      loader: () => _loadStudyBundle(directoryPath),
      openViewerOnSuccess: true,
    );
  }

  Future<void> loadStudyFromFiles(List<String> filePaths) async {
    final sourceLabel = filePaths.length == 1
        ? filePaths.first
        : '${filePaths.length} selected files';

    await _loadBundle(
      sourceLabel: sourceLabel,
      multipleStudiesContext: 'the selected files',
      loader: () => _loadStudyBundle.fromFiles(filePaths),
      openViewerOnSuccess: true,
    );
  }

  Future<void> _loadBundle({
    required String sourceLabel,
    required String multipleStudiesContext,
    required Future<DicomStudyBundle> Function() loader,
    required bool openViewerOnSuccess,
  }) async {
    state = state.copyWith(
      isBusy: true,
      activeDirectory: sourceLabel,
      errorMessage: null,
      noticeMessage: null,
      seriesThumbnails: <String, Uint8List>{},
    );

    _log.info(_tag, 'Loading bundle: $sourceLabel');

    try {
      final bundle = await loader();
      final viewerSession = await _viewerServer.registerBundle(bundle);
      final initialStudy = _preferredStudy(bundle.studies);
      final initialSeriesUid = initialStudy?.series.isNotEmpty == true
          ? initialStudy!.series.first.seriesInstanceUid
          : null;
      final initialSliceCount = initialStudy?.series.isNotEmpty == true
          ? initialStudy!.series.first.instances.length
          : 0;

      state = state.copyWith(
        isBusy: false,
        screen: openViewerOnSuccess
            ? WorkstationScreen.viewer
            : WorkstationScreen.worklist,
        bundle: bundle,
        viewerSession: viewerSession,
        selectedStudyUid: initialStudy?.studyInstanceUid,
        selectedSeriesUid: initialSeriesUid,
        activeTool: ViewerTool.windowLevel,
        viewerLayout: ViewerLayout.single,
        mprActive: false,
        layoutBeforeMpr: null,
        viewportState: ViewportOverlayState(
          totalImages: initialSliceCount,
          statusMessage: 'Viewport ready',
        ),
        seriesThumbnails: <String, Uint8List>{},
        noticeMessage: bundle.studies.length > 1
            ? '${bundle.studies.length} studies detected in $multipleStudiesContext.'
            : null,
      );
      _log.info(_tag, 'Bundle loaded: ${bundle.studies.length} studies, ${bundle.studies.fold<int>(0, (s, st) => s + st.series.length)} series');
    } catch (error, stack) {
      _log.error(_tag, 'Bundle load failed: $sourceLabel', error, stack);
      state = state.copyWith(
        isBusy: false,
        screen: WorkstationScreen.worklist,
        bundle: null,
        viewerSession: null,
        selectedStudyUid: null,
        selectedSeriesUid: null,
        viewportState: const ViewportOverlayState(),
        seriesThumbnails: <String, Uint8List>{},
        errorMessage: error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void goToWorklist() {
    state = state.copyWith(
      screen: WorkstationScreen.worklist,
      errorMessage: null,
    );
  }

  void selectStudy(String studyInstanceUid) {
    final study = state.bundle?.studies.firstWhere(
      (candidate) => candidate.studyInstanceUid == studyInstanceUid,
      orElse: () => const DicomStudy(
        studyInstanceUid: '',
        sourceDirectory: '',
        patientName: '',
        patientId: '',
        studyDate: '',
        studyDescription: '',
        series: <DicomSeries>[],
      ),
    );

    if (study == null || study.studyInstanceUid.isEmpty) {
      return;
    }

    state = state.copyWith(
      selectedStudyUid: studyInstanceUid,
      selectedSeriesUid: study.series.isEmpty
          ? null
          : study.series
                .where((s) => s.isImageModality)
                .firstOrNull
                ?.seriesInstanceUid ??
              study.series.first.seriesInstanceUid,
      viewportState: const ViewportOverlayState(),
    );
  }

  void selectSeries(String seriesInstanceUid) {
    final images =
        state.viewerSession?.seriesPayloads[seriesInstanceUid]?.imageIds;

    state = state.copyWith(
      selectedSeriesUid: seriesInstanceUid,
      viewportState: state.viewportState.copyWith(
        currentImageIndex: 0,
        totalImages: images?.length ?? 0,
      ),
    );
  }

  void setTool(ViewerTool tool) {
    state = state.copyWith(activeTool: tool);
  }

  void setLayout(ViewerLayout layout) {
    state = state.copyWith(viewerLayout: layout);
  }

  void toggleMpr(bool enabled) {
    state = state.copyWith(mprActive: enabled);
  }

  void updateViewport(ViewportOverlayState viewportState) {
    state = state.copyWith(viewportState: viewportState, errorMessage: null);
  }

  void setViewerStatus(String message) {
    state = state.copyWith(
      viewportState: state.viewportState.copyWith(statusMessage: message),
    );
  }

  void setSeriesThumbnailFromDataUrl(String seriesInstanceUid, String dataUrl) {
    final bytes = _decodeDataUrl(dataUrl);
    if (bytes == null || bytes.isEmpty) {
      return;
    }

    final updated = Map<String, Uint8List>.from(state.seriesThumbnails)
      ..[seriesInstanceUid] = bytes;

    state = state.copyWith(seriesThumbnails: updated);
  }

  void updateSeriesLoadProgress(String seriesInstanceUid, int loaded, int total) {
    if (total <= 0) {
      return;
    }

    final progress = (loaded / total).clamp(0.0, 1.0);
    final updated = Map<String, double>.from(state.seriesLoadProgress)
      ..[seriesInstanceUid] = progress;

    state = state.copyWith(seriesLoadProgress: updated);
  }

  Uint8List? _decodeDataUrl(String value) {
    if (value.isEmpty) {
      return null;
    }

    final commaIndex = value.indexOf(',');
    if (commaIndex < 0 || commaIndex + 1 >= value.length) {
      return null;
    }

    final base64Payload = value.substring(commaIndex + 1);
    try {
      return base64Decode(base64Payload);
    } catch (e) {
      _log.warn(_tag, 'Failed to decode data URL', e);
      return null;
    }
  }

  /// Clears the viewer session and returns to the worklist,
  /// showing [message] in the error banner.
  void resetToEmptyWithError(String message) {
    state = state.copyWith(
      screen: WorkstationScreen.worklist,
      bundle: null,
      viewerSession: null,
      selectedStudyUid: null,
      selectedSeriesUid: null,
      isBusy: false,
      viewportState: const ViewportOverlayState(),
      noticeMessage: null,
      seriesThumbnails: <String, Uint8List>{},
      errorMessage: message,
    );
  }

  /// Clears the current error message.
  void clearError() {
    state = state.copyWith(errorMessage: null, worklistErrorMessage: null);
  }

  DicomStudy? _preferredStudy(List<DicomStudy> studies) {
    if (studies.isEmpty) {
      return null;
    }

    final sorted = [...studies]
      ..sort((a, b) => b.series.length.compareTo(a.series.length));
    return sorted.first;
  }
}
