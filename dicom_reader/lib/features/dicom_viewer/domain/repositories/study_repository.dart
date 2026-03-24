import '../entities/dicom_models.dart';

abstract class StudyRepository {
  Future<DicomStudyBundle> loadStudyBundle(String directoryPath);

  Future<DicomStudyBundle> loadStudyBundleFromFiles(List<String> filePaths);
}
