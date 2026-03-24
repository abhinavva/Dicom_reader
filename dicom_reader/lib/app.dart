import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/dicom_viewer/presentation/pages/dicom_workstation_page.dart';

class DicomReaderApp extends StatelessWidget {
  const DicomReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dicom Reader',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark(),
      home: const DicomWorkstationPage(),
    );
  }
}
