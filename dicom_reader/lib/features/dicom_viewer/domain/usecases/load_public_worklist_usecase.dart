import '../entities/dicom_web_models.dart';
import '../repositories/dicom_web_repository.dart';

class LoadPublicWorklistUseCase {
  const LoadPublicWorklistUseCase(this._repository);

  final DicomWebRepository _repository;

  Future<List<DicomWebWorklistStudy>> call() {
    return _repository.fetchWorklistStudies();
  }
}
