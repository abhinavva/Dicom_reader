import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../../core/services/app_logger.dart';
import '../../domain/entities/dicom_models.dart';

class ParsedDicomFile {
  const ParsedDicomFile({
    required this.studyInstanceUid,
    required this.seriesInstanceUid,
    required this.patientName,
    required this.patientId,
    required this.studyDate,
    required this.studyDescription,
    required this.seriesDescription,
    required this.modality,
    required this.instance,
  });

  final String studyInstanceUid;
  final String seriesInstanceUid;
  final String patientName;
  final String patientId;
  final String studyDate;
  final String studyDescription;
  final String seriesDescription;
  final String modality;
  final DicomInstance instance;
}

class DicomParserService {
  const DicomParserService();

  static const int _maxHeaderBytes = 1024 * 1024;
  static final AppLogger _log = AppLogger.instance;
  static const String _tag = 'DicomParser';

  Future<ParsedDicomFile?> parseFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final raf = await file.open();
      try {
        final length = await raf.length();
        final headerBytes = await raf.read(
          length > _maxHeaderBytes ? _maxHeaderBytes : length,
        );
        if (headerBytes.isEmpty || !_looksLikeDicom(headerBytes)) {
          return null;
        }

        final parser = _DicomBufferParser(headerBytes);
        final result = parser.parse();
        if (!result.hasRequiredIdentifiers) {
          return null;
        }

        return ParsedDicomFile(
          studyInstanceUid: result.valueOf(_DicomTags.studyInstanceUid),
          seriesInstanceUid: result.valueOf(_DicomTags.seriesInstanceUid),
          patientName: result.valueOf(_DicomTags.patientName),
          patientId: result.valueOf(_DicomTags.patientId),
          studyDate: result.valueOf(_DicomTags.studyDate),
          studyDescription: result.valueOf(_DicomTags.studyDescription),
          seriesDescription: result.valueOf(_DicomTags.seriesDescription),
          modality: result.valueOf(_DicomTags.modality),
          instance: DicomInstance(
            filePath: filePath,
            sopInstanceUid: result.valueOf(_DicomTags.sopInstanceUid),
            instanceNumber:
                int.tryParse(
                  result.valueOf(_DicomTags.instanceNumber).split('\\').first,
                ) ??
                0,
            metadata: result.metadataEntries,
            windowCenter: _parseFirstDouble(
              result.valueOf(_DicomTags.windowCenter),
            ),
            windowWidth: _parseFirstDouble(
              result.valueOf(_DicomTags.windowWidth),
            ),
            rows: int.tryParse(result.valueOf(_DicomTags.rows)),
            columns: int.tryParse(result.valueOf(_DicomTags.columns)),
            seriesDescription: result.valueOf(_DicomTags.seriesDescription),
            modality: result.valueOf(_DicomTags.modality),
          ),
        );
      } finally {
        await raf.close();
      }
    } catch (e) {
      _log.warn(_tag, 'Failed to parse DICOM file: $filePath', e);
      return null;
    }
  }

  static bool _looksLikeDicom(Uint8List bytes) {
    if (bytes.length >= 132 &&
        ascii.decode(bytes.sublist(128, 132), allowInvalid: true) == 'DICM') {
      return true;
    }

    if (bytes.length < 8) {
      return false;
    }

    final group = _EndianReader.readUint16(bytes, 0, Endian.little);
    final element = _EndianReader.readUint16(bytes, 2, Endian.little);
    final vr1 = bytes[4];
    final vr2 = bytes[5];

    final tagLooksValid = group <= 0x7FE0 && element <= 0xFFFF;
    final vrLooksValid = vr1 >= 65 && vr1 <= 90 && vr2 >= 65 && vr2 <= 90;
    return tagLooksValid && vrLooksValid;
  }

  static double? _parseFirstDouble(String value) {
    if (value.isEmpty) {
      return null;
    }

    return double.tryParse(value.split('\\').first.trim());
  }
}

class _DicomBufferParser {
  _DicomBufferParser(this._data);

  final Uint8List _data;
  final Map<int, String> _values = <int, String>{};

  _DicomParseResult parse() {
    var offset = 0;
    var datasetSyntax = const _TransferSyntax(
      explicitVr: true,
      endian: Endian.little,
    );

    if (_data.length >= 132 &&
        ascii.decode(_data.sublist(128, 132), allowInvalid: true) == 'DICM') {
      offset = 132;
      offset = _parseDataset(
        offset: offset,
        syntax: const _TransferSyntax(explicitVr: true, endian: Endian.little),
        stopAfterMetaInformation: true,
      );
      datasetSyntax = _resolveTransferSyntax(
        _values[_DicomTags.transferSyntaxUid] ?? '',
      );
    } else {
      datasetSyntax = _looksLikeExplicitVr(offset)
          ? const _TransferSyntax(explicitVr: true, endian: Endian.little)
          : const _TransferSyntax(explicitVr: false, endian: Endian.little);
    }

    _parseDataset(offset: offset, syntax: datasetSyntax);

    final metadataEntries =
        _values.entries
            .where((entry) => _interestingTags.containsKey(entry.key))
            .map(
              (entry) => DicomTagEntry(
                tag: _formatTag(entry.key),
                label: _interestingTags[entry.key]!.label,
                value: entry.value,
              ),
            )
            .where((entry) => entry.value.isNotEmpty)
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));

    return _DicomParseResult(
      values: Map<int, String>.unmodifiable(_values),
      metadataEntries: metadataEntries,
    );
  }

  int _parseDataset({
    required int offset,
    required _TransferSyntax syntax,
    bool stopAfterMetaInformation = false,
  }) {
    while (offset + 8 <= _data.length) {
      try {
        final group = _EndianReader.readUint16(_data, offset, syntax.endian);
        final element = _EndianReader.readUint16(
          _data,
          offset + 2,
          syntax.endian,
        );
        final tag = (group << 16) | element;

        if (stopAfterMetaInformation && group != 0x0002) {
          return offset;
        }

        if (tag == _DicomTags.pixelData) {
          return _data.length;
        }

        String vr = '';
        late int valueLength;
        late int valueOffset;

        if (syntax.explicitVr) {
          if (offset + 8 > _data.length) {
            return _data.length;
          }

          vr = ascii.decode(
            _data.sublist(offset + 4, offset + 6),
            allowInvalid: true,
          );
          if (_longValueRepresentations.contains(vr)) {
            if (offset + 12 > _data.length) {
              return _data.length;
            }
            valueLength = _EndianReader.readUint32(
              _data,
              offset + 8,
              syntax.endian,
            );
            valueOffset = offset + 12;
          } else {
            valueLength = _EndianReader.readUint16(
              _data,
              offset + 6,
              syntax.endian,
            );
            valueOffset = offset + 8;
          }
        } else {
          valueLength = _EndianReader.readUint32(
            _data,
            offset + 4,
            syntax.endian,
          );
          valueOffset = offset + 8;
          vr = _interestingTags[tag]?.vr ?? 'UN';
        }

        if (valueLength == 0xFFFFFFFF) {
          return _data.length;
        }

        final nextOffset = valueOffset + valueLength;
        if (nextOffset > _data.length || valueOffset > _data.length) {
          return _data.length;
        }

        final definition = _interestingTags[tag];
        if (definition != null) {
          _values[tag] = _decodeValue(
            bytes: _data.sublist(valueOffset, nextOffset),
            vr: vr,
          );
        }

        offset = nextOffset;
        if (_hasCoreIdentifiers) {
          final hasViewerSummary =
              _values.containsKey(_DicomTags.seriesDescription) &&
              _values.containsKey(_DicomTags.modality);
          if (hasViewerSummary && offset > 256 * 1024) {
            return _data.length;
          }
        }
      } catch (e) {
        AppLogger.instance.debug('DicomParser', 'Corrupted element at offset $offset — stopping parse');
        return _data.length;
      }
    }

    return offset;
  }

  bool _looksLikeExplicitVr(int offset) {
    if (offset + 6 >= _data.length) {
      return false;
    }

    final vr1 = _data[offset + 4];
    final vr2 = _data[offset + 5];
    return vr1 >= 65 && vr1 <= 90 && vr2 >= 65 && vr2 <= 90;
  }

  bool get _hasCoreIdentifiers {
    return (_values[_DicomTags.studyInstanceUid] ?? '').isNotEmpty &&
        (_values[_DicomTags.seriesInstanceUid] ?? '').isNotEmpty &&
        (_values[_DicomTags.sopInstanceUid] ?? '').isNotEmpty;
  }

  static _TransferSyntax _resolveTransferSyntax(String transferSyntaxUid) {
    switch (transferSyntaxUid.trim()) {
      case '1.2.840.10008.1.2':
        return const _TransferSyntax(explicitVr: false, endian: Endian.little);
      case '1.2.840.10008.1.2.2':
        return const _TransferSyntax(explicitVr: true, endian: Endian.big);
      default:
        return const _TransferSyntax(explicitVr: true, endian: Endian.little);
    }
  }

  static String _decodeValue({required Uint8List bytes, required String vr}) {
    if (bytes.isEmpty) {
      return '';
    }

    if (vr == 'US' && bytes.length >= 2) {
      return _EndianReader.readUint16(bytes, 0, Endian.little).toString();
    }

    if (vr == 'UL' && bytes.length >= 4) {
      return _EndianReader.readUint32(bytes, 0, Endian.little).toString();
    }

    final decoded = latin1.decode(bytes, allowInvalid: true);
    return decoded.replaceAll('\u0000', '').trim().replaceAll('^', ' ');
  }

  static String _formatTag(int tag) {
    final group = (tag >> 16).toRadixString(16).padLeft(4, '0').toUpperCase();
    final element = (tag & 0xFFFF)
        .toRadixString(16)
        .padLeft(4, '0')
        .toUpperCase();
    return '($group,$element)';
  }

  static const Map<int, _TagDefinition>
  _interestingTags = <int, _TagDefinition>{
    _DicomTags.transferSyntaxUid: _TagDefinition(
      label: 'Transfer Syntax UID',
      vr: 'UI',
    ),
    _DicomTags.patientName: _TagDefinition(label: 'Patient Name', vr: 'PN'),
    _DicomTags.patientId: _TagDefinition(label: 'Patient ID', vr: 'LO'),
    _DicomTags.studyDate: _TagDefinition(label: 'Study Date', vr: 'DA'),
    _DicomTags.modality: _TagDefinition(label: 'Modality', vr: 'CS'),
    _DicomTags.studyDescription: _TagDefinition(
      label: 'Study Description',
      vr: 'LO',
    ),
    _DicomTags.seriesDescription: _TagDefinition(
      label: 'Series Description',
      vr: 'LO',
    ),
    _DicomTags.sopInstanceUid: _TagDefinition(
      label: 'SOP Instance UID',
      vr: 'UI',
    ),
    _DicomTags.studyInstanceUid: _TagDefinition(
      label: 'Study Instance UID',
      vr: 'UI',
    ),
    _DicomTags.seriesInstanceUid: _TagDefinition(
      label: 'Series Instance UID',
      vr: 'UI',
    ),
    _DicomTags.instanceNumber: _TagDefinition(
      label: 'Instance Number',
      vr: 'IS',
    ),
    _DicomTags.windowCenter: _TagDefinition(label: 'Window Center', vr: 'DS'),
    _DicomTags.windowWidth: _TagDefinition(label: 'Window Width', vr: 'DS'),
    _DicomTags.rows: _TagDefinition(label: 'Rows', vr: 'US'),
    _DicomTags.columns: _TagDefinition(label: 'Columns', vr: 'US'),
    _DicomTags.sliceThickness: _TagDefinition(
      label: 'Slice Thickness',
      vr: 'DS',
    ),
    _DicomTags.pixelSpacing: _TagDefinition(label: 'Pixel Spacing', vr: 'DS'),
    _DicomTags.bodyPartExamined: _TagDefinition(label: 'Body Part', vr: 'CS'),
    _DicomTags.institutionName: _TagDefinition(label: 'Institution', vr: 'LO'),
    _DicomTags.manufacturer: _TagDefinition(label: 'Manufacturer', vr: 'LO'),
    _DicomTags.referringPhysician: _TagDefinition(
      label: 'Referring Physician',
      vr: 'PN',
    ),
  };

  static const Set<String> _longValueRepresentations = <String>{
    'OB',
    'OD',
    'OF',
    'OL',
    'OV',
    'OW',
    'SQ',
    'SV',
    'UC',
    'UR',
    'UT',
    'UV',
    'UN',
  };
}

class _DicomParseResult {
  const _DicomParseResult({
    required this.values,
    required this.metadataEntries,
  });

  final Map<int, String> values;
  final List<DicomTagEntry> metadataEntries;

  String valueOf(int tag) => values[tag] ?? '';

  bool get hasRequiredIdentifiers =>
      valueOf(_DicomTags.studyInstanceUid).isNotEmpty &&
      valueOf(_DicomTags.seriesInstanceUid).isNotEmpty &&
      valueOf(_DicomTags.sopInstanceUid).isNotEmpty;
}

class _TagDefinition {
  const _TagDefinition({required this.label, required this.vr});

  final String label;
  final String vr;
}

class _TransferSyntax {
  const _TransferSyntax({required this.explicitVr, required this.endian});

  final bool explicitVr;
  final Endian endian;
}

class _EndianReader {
  static int readUint16(Uint8List bytes, int offset, Endian endian) {
    final data = ByteData.sublistView(bytes, offset, offset + 2);
    return data.getUint16(0, endian);
  }

  static int readUint32(Uint8List bytes, int offset, Endian endian) {
    final data = ByteData.sublistView(bytes, offset, offset + 4);
    return data.getUint32(0, endian);
  }
}

class _DicomTags {
  static const int transferSyntaxUid = 0x00020010;
  static const int sopInstanceUid = 0x00080018;
  static const int studyDate = 0x00080020;
  static const int modality = 0x00080060;
  static const int manufacturer = 0x00080070;
  static const int institutionName = 0x00080080;
  static const int referringPhysician = 0x00080090;
  static const int studyDescription = 0x00081030;
  static const int seriesDescription = 0x0008103E;
  static const int sliceThickness = 0x00180050;
  static const int patientName = 0x00100010;
  static const int patientId = 0x00100020;
  static const int bodyPartExamined = 0x00180015;
  static const int studyInstanceUid = 0x0020000D;
  static const int seriesInstanceUid = 0x0020000E;
  static const int instanceNumber = 0x00200013;
  static const int rows = 0x00280010;
  static const int columns = 0x00280011;
  static const int pixelSpacing = 0x00280030;
  static const int windowCenter = 0x00281050;
  static const int windowWidth = 0x00281051;
  static const int pixelData = 0x7FE00010;
}
