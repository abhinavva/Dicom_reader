import 'dart:convert';
import 'dart:io';

import '../../domain/entities/dicom_models.dart';
import '../../domain/entities/dicom_web_models.dart';
import '../../domain/repositories/dicom_web_repository.dart';

class PublicDicomWebRepository implements DicomWebRepository {
  PublicDicomWebRepository({List<DicomWebEndpoint>? endpoints})
    : _endpoints = endpoints ?? _defaultEndpoints;

  final List<DicomWebEndpoint> _endpoints;

  static const List<DicomWebEndpoint> _defaultEndpoints = <DicomWebEndpoint>[
    DicomWebEndpoint(
      id: 'dcmjs',
      name: 'DCM4CHEE Public Archive',
      qidoRoot: 'https://server.dcmjs.org/dcm4chee-arc/aets/DCM4CHEE/rs',
      wadoUriRoot: 'https://server.dcmjs.org/dcm4chee-arc/aets/DCM4CHEE/wado',
      maxStudies: 22,
      maxSeriesPerStudy: 20,
      maxInstancesPerSeries: 700,
    ),
    DicomWebEndpoint(
      id: 'orthanc-demo',
      name: 'Orthanc Demo Server',
      qidoRoot: 'https://demo.orthanc-server.com/dicom-web',
      wadoUriRoot: 'https://demo.orthanc-server.com/wado',
      maxStudies: 20,
      maxSeriesPerStudy: 18,
      maxInstancesPerSeries: 600,
    ),
    DicomWebEndpoint(
      id: 'orthanc-uclouvain',
      name: 'Orthanc UCLouvain Demo',
      qidoRoot: 'https://orthanc.uclouvain.be/demo/dicom-web',
      wadoUriRoot: 'https://orthanc.uclouvain.be/demo/wado',
      maxStudies: 18,
      maxSeriesPerStudy: 16,
      maxInstancesPerSeries: 500,
    ),
  ];

  @override
  List<DicomWebEndpoint> get publicEndpoints =>
      List<DicomWebEndpoint>.unmodifiable(_endpoints);

  @override
  Future<List<DicomWebWorklistStudy>> fetchWorklistStudies() async {
    final responseSets = await Future.wait(
      _endpoints.map(_fetchStudiesForEndpoint),
    );

    final merged = responseSets.expand((items) => items).toList()
      ..sort((a, b) {
        final byDate = b.studyDate.compareTo(a.studyDate);
        if (byDate != 0) {
          return byDate;
        }

        final byEndpoint = a.endpoint.name.compareTo(b.endpoint.name);
        if (byEndpoint != 0) {
          return byEndpoint;
        }

        return a.patientName.compareTo(b.patientName);
      });

    if (merged.isEmpty) {
      throw Exception(
        'Could not load studies from the configured public DICOMweb servers. '
        'Please check your network connection and try refresh.',
      );
    }

    return merged;
  }

  @override
  Future<DicomStudyBundle> loadStudyFromWorklist(
    DicomWebWorklistStudy study,
  ) async {
    final endpoint = study.endpoint;
    final encodedStudyUid = Uri.encodeComponent(study.studyInstanceUid);

    final seriesRecords = await _getQidoList(
      _qidoUri(endpoint, 'studies/$encodedStudyUid/series', <String, String>{
        'includefield': 'all',
        'limit': endpoint.maxSeriesPerStudy.toString(),
      }),
    );

    if (seriesRecords.isEmpty) {
      throw Exception('No series were returned for the selected study.');
    }

    final seriesList = <DicomSeries>[];

    for (final record in seriesRecords) {
      final seriesUid = _readTagString(record, '0020000E');
      if (seriesUid.isEmpty) {
        continue;
      }

      final seriesDescription = _readTagString(record, '0008103E');
      final modality = _readTagString(record, '00080060');

      final instances = await _fetchSeriesInstances(
        endpoint: endpoint,
        studyUid: study.studyInstanceUid,
        seriesUid: seriesUid,
        defaultSeriesDescription: seriesDescription,
        defaultModality: modality,
      );

      if (instances.isEmpty) {
        continue;
      }

      seriesList.add(
        DicomSeries(
          studyInstanceUid: study.studyInstanceUid,
          seriesInstanceUid: seriesUid,
          description: seriesDescription.isEmpty
              ? 'Unnamed Series'
              : seriesDescription,
          modality: modality.isEmpty ? 'OT' : modality,
          instances: instances,
        ),
      );
    }

    if (seriesList.isEmpty) {
      throw Exception(
        'No renderable instances were available for this study on ${endpoint.name}.',
      );
    }

    seriesList.sort((a, b) {
      final byModality = a.modality.compareTo(b.modality);
      if (byModality != 0) {
        return byModality;
      }
      return a.description.compareTo(b.description);
    });

    final studyModel = DicomStudy(
      studyInstanceUid: study.studyInstanceUid,
      sourceDirectory: endpoint.name,
      patientName: study.patientName,
      patientId: study.patientId,
      studyDate: study.studyDate,
      studyDescription: study.studyDescription,
      series: seriesList,
    );

    return DicomStudyBundle(
      sourceDirectory: endpoint.name,
      studies: <DicomStudy>[studyModel],
    );
  }

  Future<List<DicomWebWorklistStudy>> _fetchStudiesForEndpoint(
    DicomWebEndpoint endpoint,
  ) async {
    try {
      final records = await _getQidoList(
        _qidoUri(endpoint, 'studies', <String, String>{
          'includefield': 'all',
          'limit': endpoint.maxStudies.toString(),
        }),
      );

      final items = <DicomWebWorklistStudy>[];
      for (final record in records) {
        final studyUid = _readTagString(record, '0020000D');
        if (studyUid.isEmpty) {
          continue;
        }

        final modalities = _readTagStringList(record, '00080061');
        final seriesCount = _readTagInt(record, '00201206') ?? 0;

        items.add(
          DicomWebWorklistStudy(
            endpoint: endpoint,
            studyInstanceUid: studyUid,
            patientName: _readPersonName(record, '00100010'),
            patientId: _readTagString(record, '00100020'),
            studyDate: _readTagString(record, '00080020'),
            studyDescription: _readTagString(record, '00081030'),
            modalitiesInStudy: modalities,
            seriesCount: seriesCount,
          ),
        );
      }

      return items;
    } catch (_) {
      return const <DicomWebWorklistStudy>[];
    }
  }

  Future<List<DicomInstance>> _fetchSeriesInstances({
    required DicomWebEndpoint endpoint,
    required String studyUid,
    required String seriesUid,
    required String defaultSeriesDescription,
    required String defaultModality,
  }) async {
    final encodedStudyUid = Uri.encodeComponent(studyUid);
    final encodedSeriesUid = Uri.encodeComponent(seriesUid);

    final records = await _getQidoList(
      _qidoUri(
        endpoint,
        'studies/$encodedStudyUid/series/$encodedSeriesUid/instances',
        <String, String>{
          'includefield': 'all',
          'limit': endpoint.maxInstancesPerSeries.toString(),
        },
      ),
    );

    final instances = <DicomInstance>[];
    for (final record in records) {
      final sopInstanceUid = _readTagString(record, '00080018');
      if (sopInstanceUid.isEmpty) {
        continue;
      }

      final instanceNumber = _readTagInt(record, '00200013') ?? 0;
      final rows = _readTagInt(record, '00280010');
      final columns = _readTagInt(record, '00280011');
      final windowCenter = _readTagDouble(record, '00281050');
      final windowWidth = _readTagDouble(record, '00281051');
      final resolvedSeriesDescription =
          _readTagString(record, '0008103E').isEmpty
          ? defaultSeriesDescription
          : _readTagString(record, '0008103E');
      final resolvedModality = _readTagString(record, '00080060').isEmpty
          ? defaultModality
          : _readTagString(record, '00080060');

      final wadoUri = _buildWadoUri(
        endpoint: endpoint,
        studyUid: studyUid,
        seriesUid: seriesUid,
        sopInstanceUid: sopInstanceUid,
      );

      instances.add(
        DicomInstance(
          filePath:
              'remote://${endpoint.id}/${Uri.encodeComponent(studyUid)}/${Uri.encodeComponent(seriesUid)}/${Uri.encodeComponent(sopInstanceUid)}',
          sopInstanceUid: sopInstanceUid,
          instanceNumber: instanceNumber,
          metadata: _buildMetadataEntries(record),
          windowCenter: windowCenter,
          windowWidth: windowWidth,
          rows: rows,
          columns: columns,
          seriesDescription: resolvedSeriesDescription,
          modality: resolvedModality,
          remoteWadoUri: wadoUri,
          remoteHeaders: const <String, String>{'Accept': 'application/dicom'},
        ),
      );
    }

    instances.sort((a, b) {
      final byInstance = a.instanceNumber.compareTo(b.instanceNumber);
      if (byInstance != 0) {
        return byInstance;
      }
      return a.sopInstanceUid.compareTo(b.sopInstanceUid);
    });

    return instances;
  }

  String _buildWadoUri({
    required DicomWebEndpoint endpoint,
    required String studyUid,
    required String seriesUid,
    required String sopInstanceUid,
  }) {
    if (endpoint.wadoUriRoot.isNotEmpty) {
      final base = Uri.parse(endpoint.wadoUriRoot);
      final mergedQuery = Map<String, String>.from(base.queryParameters)
        ..addAll(<String, String>{
          'requestType': 'WADO',
          'studyUID': studyUid,
          'seriesUID': seriesUid,
          'objectUID': sopInstanceUid,
          'contentType': 'application/dicom',
        });

      return base.replace(queryParameters: mergedQuery).toString();
    }

    final fallback = _qidoUri(
      endpoint,
      'studies/${Uri.encodeComponent(studyUid)}/series/${Uri.encodeComponent(seriesUid)}/instances/${Uri.encodeComponent(sopInstanceUid)}',
      const <String, String>{},
    );
    return fallback.toString();
  }

  Uri _qidoUri(
    DicomWebEndpoint endpoint,
    String relativePath,
    Map<String, String> query,
  ) {
    final root = endpoint.qidoRoot.endsWith('/')
        ? endpoint.qidoRoot
        : '${endpoint.qidoRoot}/';
    final base = Uri.parse(root).resolve(relativePath);
    final merged = Map<String, String>.from(base.queryParameters)
      ..addAll(query);
    return base.replace(queryParameters: merged);
  }

  Future<List<Map<String, dynamic>>> _getQidoList(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 25)
      ..idleTimeout = const Duration(seconds: 25);

    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/dicom+json, application/json',
      );

      final response = await request.close();
      final bodyBytes = await response.fold<List<int>>(<int>[], (
        previous,
        element,
      ) {
        previous.addAll(element);
        return previous;
      });

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('QIDO request failed (${response.statusCode}) at $uri');
      }

      if (bodyBytes.isEmpty) {
        return const <Map<String, dynamic>>[];
      }

      final decoded = jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
      if (decoded is! List) {
        return const <Map<String, dynamic>>[];
      }

      return decoded
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  List<DicomTagEntry> _buildMetadataEntries(Map<String, dynamic> dataset) {
    final entries = <DicomTagEntry>[];

    for (final item in _metadataTagDefinitions.entries) {
      final tag = item.key;
      final label = item.value;
      final value = tag == '00100010'
          ? _readPersonName(dataset, tag)
          : _readTagString(dataset, tag);

      if (value.isEmpty) {
        continue;
      }

      entries.add(
        DicomTagEntry(tag: _formatTag(tag), label: label, value: value),
      );
    }

    entries.sort((a, b) => a.label.compareTo(b.label));
    return entries;
  }

  String _formatTag(String tag) {
    final normalized = tag.toUpperCase().replaceAll(',', '').padLeft(8, '0');
    final group = normalized.substring(0, 4);
    final element = normalized.substring(4, 8);
    return '($group,$element)';
  }

  String _readPersonName(Map<String, dynamic> dataset, String tag) {
    final values = _readTagValues(dataset, tag);
    if (values.isEmpty) {
      return '';
    }

    final first = values.first;
    if (first is Map) {
      final map = Map<String, dynamic>.from(first);
      final alphabetic = map['Alphabetic']?.toString() ?? '';
      if (alphabetic.isNotEmpty) {
        return alphabetic.replaceAll('^', ' ').trim();
      }

      for (final value in map.values) {
        final text = value?.toString() ?? '';
        if (text.isNotEmpty) {
          return text.replaceAll('^', ' ').trim();
        }
      }
    }

    return first.toString().replaceAll('^', ' ').trim();
  }

  String _readTagString(Map<String, dynamic> dataset, String tag) {
    final values = _readTagValues(dataset, tag);
    if (values.isEmpty) {
      return '';
    }

    if (values.length > 1) {
      return values
          .map(_valueToString)
          .where((item) => item.isNotEmpty)
          .join('\\');
    }

    return _valueToString(values.first);
  }

  List<String> _readTagStringList(Map<String, dynamic> dataset, String tag) {
    final values = _readTagValues(dataset, tag);
    return values.map(_valueToString).where((item) => item.isNotEmpty).toList();
  }

  int? _readTagInt(Map<String, dynamic> dataset, String tag) {
    final values = _readTagValues(dataset, tag);
    if (values.isEmpty) {
      return null;
    }

    final raw = _valueToString(values.first);
    return int.tryParse(raw);
  }

  double? _readTagDouble(Map<String, dynamic> dataset, String tag) {
    final values = _readTagValues(dataset, tag);
    if (values.isEmpty) {
      return null;
    }

    final raw = _valueToString(values.first);
    return double.tryParse(raw);
  }

  List<dynamic> _readTagValues(Map<String, dynamic> dataset, String tag) {
    final normalized = tag.toUpperCase().replaceAll(',', '');

    for (final entry in dataset.entries) {
      final key = entry.key.toUpperCase().replaceAll(',', '');
      if (key != normalized) {
        continue;
      }

      if (entry.value is! Map) {
        return const <dynamic>[];
      }

      final map = Map<String, dynamic>.from(entry.value as Map);
      final value = map['Value'];
      if (value is List) {
        return value;
      }
      return const <dynamic>[];
    }

    return const <dynamic>[];
  }

  String _valueToString(dynamic value) {
    if (value == null) {
      return '';
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final alphabetic = map['Alphabetic']?.toString() ?? '';
      if (alphabetic.isNotEmpty) {
        return alphabetic.replaceAll('^', ' ').trim();
      }

      for (final entry in map.entries) {
        final text = entry.value?.toString() ?? '';
        if (text.isNotEmpty) {
          return text.replaceAll('^', ' ').trim();
        }
      }
      return '';
    }

    return value.toString().replaceAll('^', ' ').trim();
  }

  static const Map<String, String> _metadataTagDefinitions = <String, String>{
    '00080060': 'Modality',
    '00080020': 'Study Date',
    '00081030': 'Study Description',
    '0008103E': 'Series Description',
    '00100010': 'Patient Name',
    '00100020': 'Patient ID',
    '0020000D': 'Study Instance UID',
    '0020000E': 'Series Instance UID',
    '00080018': 'SOP Instance UID',
    '00200013': 'Instance Number',
    '00280010': 'Rows',
    '00280011': 'Columns',
    '00281050': 'Window Center',
    '00281051': 'Window Width',
    '00080080': 'Institution',
    '00080070': 'Manufacturer',
  };
}
