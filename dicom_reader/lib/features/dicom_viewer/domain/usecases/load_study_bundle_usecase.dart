import '../entities/dicom_models.dart';
import '../repositories/study_repository.dart';

class LoadStudyBundleUseCase {
  const LoadStudyBundleUseCase(this._repository);

  final StudyRepository _repository;

  Future<DicomStudyBundle> call(String directoryPath) {
    return _repository.loadStudyBundle(directoryPath);
  }

  Future<DicomStudyBundle> fromFiles(List<String> filePaths) {
    return _repository.loadStudyBundleFromFiles(filePaths);
  }
}
