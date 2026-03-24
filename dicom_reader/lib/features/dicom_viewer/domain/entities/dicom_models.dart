class DicomTagEntry {
  const DicomTagEntry({
    required this.tag,
    required this.label,
    required this.value,
  });

  final String tag;
  final String label;
  final String value;
}

class DicomInstance {
  const DicomInstance({
    required this.filePath,
    required this.sopInstanceUid,
    required this.instanceNumber,
    required this.metadata,
    this.windowCenter,
    this.windowWidth,
    this.rows,
    this.columns,
    this.seriesDescription = '',
    this.modality = '',
    this.remoteWadoUri,
    this.remoteHeaders = const <String, String>{},
  });

  final String filePath;
  final String sopInstanceUid;
  final int instanceNumber;
  final List<DicomTagEntry> metadata;
  final double? windowCenter;
  final double? windowWidth;
  final int? rows;
  final int? columns;
  final String seriesDescription;
  final String modality;
  final String? remoteWadoUri;
  final Map<String, String> remoteHeaders;
}

class DicomSeries {
  const DicomSeries({
    required this.studyInstanceUid,
    required this.seriesInstanceUid,
    required this.description,
    required this.modality,
    required this.instances,
  });

  final String studyInstanceUid;
  final String seriesInstanceUid;
  final String description;
  final String modality;
  final List<DicomInstance> instances;

  DicomInstance get leadInstance => instances.first;
}

class DicomStudy {
  const DicomStudy({
    required this.studyInstanceUid,
    required this.sourceDirectory,
    required this.patientName,
    required this.patientId,
    required this.studyDate,
    required this.studyDescription,
    required this.series,
  });

  final String studyInstanceUid;
  final String sourceDirectory;
  final String patientName;
  final String patientId;
  final String studyDate;
  final String studyDescription;
  final List<DicomSeries> series;
}

class DicomStudyBundle {
  const DicomStudyBundle({
    required this.sourceDirectory,
    required this.studies,
  });

  final String sourceDirectory;
  final List<DicomStudy> studies;

  int get totalSeriesCount {
    return studies.fold<int>(0, (total, study) => total + study.series.length);
  }
}
