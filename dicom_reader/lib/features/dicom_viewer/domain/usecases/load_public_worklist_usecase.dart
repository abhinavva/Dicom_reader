import '../entities/dicom_web_models.dart';
import '../repositories/dicom_web_repository.dart';

class LoadPublicWorklistUseCase {
  const LoadPublicWorklistUseCase(this._repository);

  final DicomWebRepository _repository;

  List<DicomWebEndpoint> get availableEndpoints => _repository.publicEndpoints;

  Future<List<DicomWebWorklistStudy>> call({
    DicomWebEndpoint? endpoint,
    int offset = 0,
    int limit = 10,
  }) {
    return _repository.fetchWorklistStudies(
      endpoint: endpoint,
      offset: offset,
      limit: limit,
    );
  }
}
