import '../services/study_directory_picker.dart';

class PickDicomFilesUseCase {
  const PickDicomFilesUseCase(this._picker);

  final StudyDirectoryPicker _picker;

  Future<List<String>> call() {
    return _picker.pickDicomFiles();
  }
}
