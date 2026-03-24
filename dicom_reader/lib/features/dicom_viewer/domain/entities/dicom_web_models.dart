class DicomWebEndpoint {
  const DicomWebEndpoint({
    required this.id,
    required this.name,
    required this.qidoRoot,
    required this.wadoUriRoot,
    this.maxStudies = 20,
    this.maxSeriesPerStudy = 24,
    this.maxInstancesPerSeries = 700,
  });

  final String id;
  final String name;
  final String qidoRoot;
  final String wadoUriRoot;
  final int maxStudies;
  final int maxSeriesPerStudy;
  final int maxInstancesPerSeries;
}

class DicomWebWorklistStudy {
  const DicomWebWorklistStudy({
    required this.endpoint,
    required this.studyInstanceUid,
    required this.patientName,
    required this.patientId,
    required this.studyDate,
    required this.studyDescription,
    required this.modalitiesInStudy,
    required this.seriesCount,
  });

  final DicomWebEndpoint endpoint;
  final String studyInstanceUid;
  final String patientName;
  final String patientId;
  final String studyDate;
  final String studyDescription;
  final List<String> modalitiesInStudy;
  final int seriesCount;
}
