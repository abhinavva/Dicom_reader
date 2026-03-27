import '../entities/dicom_models.dart';
import '../entities/dicom_web_models.dart';

abstract class DicomWebRepository {
  List<DicomWebEndpoint> get publicEndpoints;

  Future<List<DicomWebWorklistStudy>> fetchWorklistStudies({
    DicomWebEndpoint? endpoint,
    int offset = 0,
    int limit = 10,
  });

  Future<DicomStudyBundle> loadStudyFromWorklist(DicomWebWorklistStudy study);
}
