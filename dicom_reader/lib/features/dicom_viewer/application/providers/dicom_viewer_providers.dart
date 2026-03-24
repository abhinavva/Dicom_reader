import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/dicom_web_repository.dart';
import '../../domain/repositories/study_repository.dart';
import '../../domain/services/study_directory_picker.dart';
import '../../domain/usecases/load_public_study_usecase.dart';
import '../../domain/usecases/load_public_worklist_usecase.dart';
import '../../domain/usecases/load_study_bundle_usecase.dart';
import '../../domain/usecases/pick_dicom_files_usecase.dart';
import '../../domain/usecases/pick_study_directory_usecase.dart';
import '../../infrastructure/repositories/local_dicom_study_repository.dart';
import '../../infrastructure/repositories/public_dicom_web_repository.dart';
import '../../infrastructure/services/dicom_parser_service.dart';
import '../../infrastructure/services/local_viewer_server.dart';
import '../dicom_viewer_controller.dart';
import '../dicom_viewer_state.dart';

final dicomParserServiceProvider = Provider<DicomParserService>((ref) {
  return const DicomParserService();
});

final studyRepositoryProvider = Provider<StudyRepository>((ref) {
  return LocalDicomStudyRepository(ref.watch(dicomParserServiceProvider));
});

final dicomWebRepositoryProvider = Provider<DicomWebRepository>((ref) {
  return PublicDicomWebRepository();
});

final studyDirectoryPickerProvider = Provider<StudyDirectoryPicker>((ref) {
  return const SystemStudyDirectoryPicker();
});

final loadStudyBundleUseCaseProvider = Provider<LoadStudyBundleUseCase>((ref) {
  return LoadStudyBundleUseCase(ref.watch(studyRepositoryProvider));
});

final loadPublicWorklistUseCaseProvider = Provider<LoadPublicWorklistUseCase>((
  ref,
) {
  return LoadPublicWorklistUseCase(ref.watch(dicomWebRepositoryProvider));
});

final loadPublicStudyUseCaseProvider = Provider<LoadPublicStudyUseCase>((ref) {
  return LoadPublicStudyUseCase(ref.watch(dicomWebRepositoryProvider));
});

final pickStudyDirectoryUseCaseProvider = Provider<PickStudyDirectoryUseCase>((
  ref,
) {
  return PickStudyDirectoryUseCase(ref.watch(studyDirectoryPickerProvider));
});

final pickDicomFilesUseCaseProvider = Provider<PickDicomFilesUseCase>((ref) {
  return PickDicomFilesUseCase(ref.watch(studyDirectoryPickerProvider));
});

final localViewerServerProvider = Provider<LocalViewerServer>((ref) {
  final server = LocalViewerServer();
  ref.onDispose(server.dispose);
  return server;
});

final dicomViewerControllerProvider =
    StateNotifierProvider<DicomViewerController, DicomViewerState>((ref) {
      return DicomViewerController(
        pickDirectory: ref.watch(pickStudyDirectoryUseCaseProvider),
        pickFiles: ref.watch(pickDicomFilesUseCaseProvider),
        loadStudyBundle: ref.watch(loadStudyBundleUseCaseProvider),
        loadPublicWorklist: ref.watch(loadPublicWorklistUseCaseProvider),
        loadPublicStudy: ref.watch(loadPublicStudyUseCaseProvider),
        viewerServer: ref.watch(localViewerServerProvider),
      );
    });

class SystemStudyDirectoryPicker implements StudyDirectoryPicker {
  const SystemStudyDirectoryPicker();

  @override
  Future<String?> pickStudyDirectory() {
    return getDirectoryPath(confirmButtonText: 'Load Folder');
  }

  @override
  Future<List<String>> pickDicomFiles() async {
    final files = await openFiles(confirmButtonText: 'Open DICOM Files');
    return files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList();
  }
}
