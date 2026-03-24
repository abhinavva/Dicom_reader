import '../entities/dicom_models.dart';
import '../entities/dicom_web_models.dart';

abstract class DicomWebRepository {
  List<DicomWebEndpoint> get publicEndpoints;

  Future<List<DicomWebWorklistStudy>> fetchWorklistStudies();

  Future<DicomStudyBundle> loadStudyFromWorklist(DicomWebWorklistStudy study);
}
