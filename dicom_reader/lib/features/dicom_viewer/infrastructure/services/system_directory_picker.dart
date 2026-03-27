import 'package:file_selector/file_selector.dart';

import '../../domain/services/study_directory_picker.dart';

class SystemStudyDirectoryPicker implements StudyDirectoryPicker {
  const SystemStudyDirectoryPicker();

  @override
  Future<String?> pickStudyDirectory() {
    return getDirectoryPath(confirmButtonText: 'Load Folder');
  }

  @override
  Future<List<String>> pickDicomFiles() async {
    final files = await openFiles(confirmButtonText: 'Open DICOM Files');
    return files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList();
  }
}
