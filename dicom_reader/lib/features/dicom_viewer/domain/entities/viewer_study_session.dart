class ViewerSeriesPayload {
  const ViewerSeriesPayload({
    required this.studyInstanceUid,
    required this.seriesInstanceUid,
    required this.imageIds,
  });

  final String studyInstanceUid;
  final String seriesInstanceUid;
  final List<String> imageIds;

  Map<String, dynamic> toJson() {
    return {
      'studyInstanceUid': studyInstanceUid,
      'seriesInstanceUid': seriesInstanceUid,
      'imageIds': imageIds,
    };
  }
}

class ViewerStudySession {
  const ViewerStudySession({
    required this.viewerUrl,
    required this.seriesPayloads,
  });

  final String viewerUrl;
  final Map<String, ViewerSeriesPayload> seriesPayloads;
}
