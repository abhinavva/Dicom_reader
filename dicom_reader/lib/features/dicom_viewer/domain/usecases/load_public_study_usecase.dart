import '../entities/dicom_models.dart';
import '../entities/dicom_web_models.dart';
import '../repositories/dicom_web_repository.dart';

class LoadPublicStudyUseCase {
  const LoadPublicStudyUseCase(this._repository);

  final DicomWebRepository _repository;

  Future<DicomStudyBundle> call(DicomWebWorklistStudy study) {
    return _repository.loadStudyFromWorklist(study);
  }
}
