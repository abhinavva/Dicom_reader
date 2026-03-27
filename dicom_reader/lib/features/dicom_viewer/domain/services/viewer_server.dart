import '../entities/dicom_models.dart';
import '../entities/viewer_study_session.dart';

abstract class ViewerServer {
  Future<ViewerStudySession> registerBundle(DicomStudyBundle bundle);
}
