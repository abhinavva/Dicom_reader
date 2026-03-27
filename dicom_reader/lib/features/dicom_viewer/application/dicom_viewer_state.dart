import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../domain/entities/dicom_models.dart';
import '../domain/entities/dicom_web_models.dart';
import '../domain/entities/viewer_models.dart';
import 'models/viewer_study_session.dart';

enum WorkstationScreen { worklist, viewer }

class DicomViewerState {
  const DicomViewerState({
    this.isBusy = false,
    this.isWorklistLoading = false,
    this.screen = WorkstationScreen.worklist,
    this.activeDirectory,
    this.bundle,
    this.viewerSession,
    this.worklistStudies = const <DicomWebWorklistStudy>[],
    this.availableEndpoints = const <DicomWebEndpoint>[],
    this.selectedEndpoint,
    this.worklistPageSize = 10,
    this.worklistOffset = 0,
    this.worklistHasMore = true,
    this.isLoadingMoreWorklist = false,
    this.selectedStudyUid,
    this.selectedSeriesUid,
    this.activeTool = ViewerTool.windowLevel,
    this.viewerLayout = ViewerLayout.single,
    this.mprActive = false,
    this.layoutBeforeMpr,
    this.viewportState = const ViewportOverlayState(),
    this.seriesThumbnails = const <String, Uint8List>{},
    this.seriesLoadProgress = const <String, double>{},
    this.errorMessage,
    this.worklistErrorMessage,
    this.noticeMessage,
  });

  final bool isBusy;
  final bool isWorklistLoading;
  final WorkstationScreen screen;
  final String? activeDirectory;
  final DicomStudyBundle? bundle;
  final ViewerStudySession? viewerSession;
  final List<DicomWebWorklistStudy> worklistStudies;
  final List<DicomWebEndpoint> availableEndpoints;
  final DicomWebEndpoint? selectedEndpoint;
  final int worklistPageSize;
  final int worklistOffset;
  final bool worklistHasMore;
  final bool isLoadingMoreWorklist;
  final String? selectedStudyUid;
  final String? selectedSeriesUid;
  final ViewerTool activeTool;
  final ViewerLayout viewerLayout;
  final bool mprActive;
  final ViewerLayout? layoutBeforeMpr;
  final ViewportOverlayState viewportState;
  final Map<String, Uint8List> seriesThumbnails;
  final Map<String, double> seriesLoadProgress;
  final String? errorMessage;
  final String? worklistErrorMessage;
  final String? noticeMessage;

  bool get hasStudy => bundle != null && bundle!.studies.isNotEmpty;

  DicomStudy? get selectedStudy {
    final studies = bundle?.studies;
    if (studies == null || studies.isEmpty) {
      return null;
    }

    return studies.firstWhereOrNull(
          (study) => study.studyInstanceUid == selectedStudyUid,
        ) ??
        studies.first;
  }

  DicomSeries? get selectedSeries {
    final study = selectedStudy;
    if (study == null || study.series.isEmpty) {
      return null;
    }

    return study.series.firstWhereOrNull(
          (series) => series.seriesInstanceUid == selectedSeriesUid,
        ) ??
        study.series.first;
  }

  DicomInstance? get selectedInstance {
    final series = selectedSeries;
    if (series == null || series.instances.isEmpty) {
      return null;
    }

    return series.leadInstance;
  }

  ViewerSeriesPayload? get selectedSeriesPayload {
    final session = viewerSession;
    final seriesUid = selectedSeries?.seriesInstanceUid;
    if (session == null || seriesUid == null) {
      return null;
    }

    return session.seriesPayloads[seriesUid];
  }

  DicomViewerState copyWith({
    bool? isBusy,
    bool? isWorklistLoading,
    WorkstationScreen? screen,
    Object? activeDirectory = _keep,
    Object? bundle = _keep,
    Object? viewerSession = _keep,
    Object? worklistStudies = _keep,
    Object? availableEndpoints = _keep,
    Object? selectedEndpoint = _keep,
    int? worklistPageSize,
    int? worklistOffset,
    bool? worklistHasMore,
    bool? isLoadingMoreWorklist,
    Object? selectedStudyUid = _keep,
    Object? selectedSeriesUid = _keep,
    ViewerTool? activeTool,
    ViewerLayout? viewerLayout,
    bool? mprActive,
    Object? layoutBeforeMpr = _keep,
    ViewportOverlayState? viewportState,
    Object? seriesThumbnails = _keep,
    Object? seriesLoadProgress = _keep,
    Object? errorMessage = _keep,
    Object? worklistErrorMessage = _keep,
    Object? noticeMessage = _keep,
  }) {
    return DicomViewerState(
      isBusy: isBusy ?? this.isBusy,
      isWorklistLoading: isWorklistLoading ?? this.isWorklistLoading,
      screen: screen ?? this.screen,
      activeDirectory: identical(activeDirectory, _keep)
          ? this.activeDirectory
          : activeDirectory as String?,
      bundle: identical(bundle, _keep)
          ? this.bundle
          : bundle as DicomStudyBundle?,
      viewerSession: identical(viewerSession, _keep)
          ? this.viewerSession
          : viewerSession as ViewerStudySession?,
      worklistStudies: identical(worklistStudies, _keep)
          ? this.worklistStudies
          : List<DicomWebWorklistStudy>.from(
              worklistStudies as List<DicomWebWorklistStudy>,
            ),
      availableEndpoints: identical(availableEndpoints, _keep)
          ? this.availableEndpoints
          : List<DicomWebEndpoint>.from(
              availableEndpoints as List<DicomWebEndpoint>,
            ),
      selectedEndpoint: identical(selectedEndpoint, _keep)
          ? this.selectedEndpoint
          : selectedEndpoint as DicomWebEndpoint?,
      worklistPageSize: worklistPageSize ?? this.worklistPageSize,
      worklistOffset: worklistOffset ?? this.worklistOffset,
      worklistHasMore: worklistHasMore ?? this.worklistHasMore,
      isLoadingMoreWorklist: isLoadingMoreWorklist ?? this.isLoadingMoreWorklist,
      selectedStudyUid: identical(selectedStudyUid, _keep)
          ? this.selectedStudyUid
          : selectedStudyUid as String?,
      selectedSeriesUid: identical(selectedSeriesUid, _keep)
          ? this.selectedSeriesUid
          : selectedSeriesUid as String?,
      activeTool: activeTool ?? this.activeTool,
      viewerLayout: viewerLayout ?? this.viewerLayout,
      mprActive: mprActive ?? this.mprActive,
      layoutBeforeMpr: identical(layoutBeforeMpr, _keep)
          ? this.layoutBeforeMpr
          : layoutBeforeMpr as ViewerLayout?,
      viewportState: viewportState ?? this.viewportState,
      seriesThumbnails: identical(seriesThumbnails, _keep)
          ? this.seriesThumbnails
          : Map<String, Uint8List>.from(
              seriesThumbnails as Map<String, Uint8List>,
            ),
      seriesLoadProgress: identical(seriesLoadProgress, _keep)
          ? this.seriesLoadProgress
          : Map<String, double>.from(
              seriesLoadProgress as Map<String, double>,
            ),
      errorMessage: identical(errorMessage, _keep)
          ? this.errorMessage
          : errorMessage as String?,
      worklistErrorMessage: identical(worklistErrorMessage, _keep)
          ? this.worklistErrorMessage
          : worklistErrorMessage as String?,
      noticeMessage: identical(noticeMessage, _keep)
          ? this.noticeMessage
          : noticeMessage as String?,
    );
  }

  static const Object _keep = Object();
}
