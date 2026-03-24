import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/dicom_models.dart';
import '../domain/entities/dicom_web_models.dart';
import '../domain/entities/viewer_models.dart';
import '../domain/usecases/load_public_study_usecase.dart';
import '../domain/usecases/load_public_worklist_usecase.dart';
import '../domain/usecases/load_study_bundle_usecase.dart';
import '../domain/usecases/pick_dicom_files_usecase.dart';
import '../domain/usecases/pick_study_directory_usecase.dart';
import '../infrastructure/services/local_viewer_server.dart';
import 'dicom_viewer_state.dart';

class DicomViewerController extends StateNotifier<DicomViewerState> {
  DicomViewerController({
    required PickStudyDirectoryUseCase pickDirectory,
    required PickDicomFilesUseCase pickFiles,
    required LoadStudyBundleUseCase loadStudyBundle,
    required LoadPublicWorklistUseCase loadPublicWorklist,
    required LoadPublicStudyUseCase loadPublicStudy,
    required LocalViewerServer viewerServer,
  }) : _pickDirectory = pickDirectory,
       _pickFiles = pickFiles,
       _loadStudyBundle = loadStudyBundle,
       _loadPublicWorklist = loadPublicWorklist,
       _loadPublicStudy = loadPublicStudy,
       _viewerServer = viewerServer,
       super(const DicomViewerState());

  final PickStudyDirectoryUseCase _pickDirectory;
  final PickDicomFilesUseCase _pickFiles;
  final LoadStudyBundleUseCase _loadStudyBundle;
  final LoadPublicWorklistUseCase _loadPublicWorklist;
  final LoadPublicStudyUseCase _loadPublicStudy;
  final LocalViewerServer _viewerServer;

  Future<void> loadPublicWorklist({bool forceRefresh = false}) async {
    if (state.isWorklistLoading) {
      return;
    }
    if (!forceRefresh && state.worklistStudies.isNotEmpty) {
      return;
    }

    state = state.copyWith(isWorklistLoading: true, worklistErrorMessage: null);

    try {
      final studies = await _loadPublicWorklist();
      state = state.copyWith(
        isWorklistLoading: false,
        worklistStudies: studies,
        worklistErrorMessage: null,
      );
    } catch (error) {
      state = state.copyWith(
        isWorklistLoading: false,
        worklistErrorMessage: error
            .toString()
            .replaceFirst('Exception: ', '')
            .trim(),
      );
    }
  }

  Future<void> openWorklistStudy(DicomWebWorklistStudy worklistStudy) async {
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
    } catch (error) {
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
    } catch (error) {
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
        viewportState: ViewportOverlayState(
          totalImages: initialSliceCount,
          statusMessage: 'Viewport ready',
        ),
        seriesThumbnails: <String, Uint8List>{},
        noticeMessage: bundle.studies.length > 1
            ? '${bundle.studies.length} studies detected in $multipleStudiesContext.'
            : null,
      );
    } catch (error) {
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
          : study.series.first.seriesInstanceUid,
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
    } catch (_) {
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
