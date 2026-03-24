import '../services/study_directory_picker.dart';

class PickStudyDirectoryUseCase {
  const PickStudyDirectoryUseCase(this._picker);

  final StudyDirectoryPicker _picker;

  Future<String?> call() {
    return _picker.pickStudyDirectory();
  }
}
