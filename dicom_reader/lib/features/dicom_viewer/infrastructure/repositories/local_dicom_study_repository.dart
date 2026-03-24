import 'dart:io';

import 'package:collection/collection.dart';

import '../../domain/entities/dicom_models.dart';
import '../../domain/repositories/study_repository.dart';
import '../services/dicom_parser_service.dart';

class LocalDicomStudyRepository implements StudyRepository {
  LocalDicomStudyRepository(this._parserService);

  final DicomParserService _parserService;
  final Map<String, DicomStudyBundle> _cache = <String, DicomStudyBundle>{};

  @override
  Future<DicomStudyBundle> loadStudyBundle(String directoryPath) async {
    final normalized = Directory(directoryPath).absolute.path;
    final cached = _cache[normalized];
    if (cached != null) {
      return cached;
    }

    final root = Directory(normalized);
    if (!await root.exists()) {
      throw Exception('The selected directory no longer exists.');
    }

    final filePaths = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        filePaths.add(entity.path);
      }
    }

    if (filePaths.isEmpty) {
      throw Exception('No files were found in the selected folder.');
    }

    final bundle = await _buildBundle(
      sourceLabel: normalized,
      filePaths: filePaths,
      emptyMessage: 'No DICOM files were detected in the selected folder.',
    );
    _cache[normalized] = bundle;
    return bundle;
  }

  @override
  Future<DicomStudyBundle> loadStudyBundleFromFiles(
    List<String> filePaths,
  ) async {
    final normalizedFiles =
        filePaths.map((path) => File(path).absolute.path).toSet().toList()
          ..sort();

    if (normalizedFiles.isEmpty) {
      throw Exception('No files were selected.');
    }

    final cacheKey = normalizedFiles.join('|');
    final cached = _cache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final bundle = await _buildBundle(
      sourceLabel: normalizedFiles.length == 1
          ? normalizedFiles.first
          : '${normalizedFiles.length} selected files',
      filePaths: normalizedFiles,
      emptyMessage: 'No DICOM files were detected in the selected files.',
    );
    _cache[cacheKey] = bundle;
    return bundle;
  }

  Future<DicomStudyBundle> _buildBundle({
    required String sourceLabel,
    required List<String> filePaths,
    required String emptyMessage,
  }) async {
    final parsedFiles = <ParsedDicomFile>[];
    for (final filePath in filePaths) {
      final parsed = await _parserService.parseFile(filePath);
      if (parsed != null) {
        parsedFiles.add(parsed);
      }
    }

    if (parsedFiles.isEmpty) {
      throw Exception(emptyMessage);
    }

    final studiesByUid = groupBy<ParsedDicomFile, String>(
      parsedFiles,
      (file) => file.studyInstanceUid,
    );

    final studies =
        studiesByUid.entries.map((studyEntry) {
          final studyFiles = studyEntry.value;
          final representative = studyFiles.first;
          final seriesByUid = groupBy<ParsedDicomFile, String>(
            studyFiles,
            (file) => file.seriesInstanceUid,
          );

          final series =
              seriesByUid.entries.map((seriesEntry) {
                final sortedInstances =
                    [...seriesEntry.value.map((file) => file.instance)]
                      ..sort((a, b) {
                        final order = a.instanceNumber.compareTo(
                          b.instanceNumber,
                        );
                        if (order != 0) {
                          return order;
                        }

                        return a.filePath.compareTo(b.filePath);
                      });

                final seriesRepresentative = seriesEntry.value.first;
                return DicomSeries(
                  studyInstanceUid: seriesRepresentative.studyInstanceUid,
                  seriesInstanceUid: seriesRepresentative.seriesInstanceUid,
                  description: seriesRepresentative.seriesDescription.isEmpty
                      ? 'Unnamed Series'
                      : seriesRepresentative.seriesDescription,
                  modality: seriesRepresentative.modality.isEmpty
                      ? 'OT'
                      : seriesRepresentative.modality,
                  instances: sortedInstances,
                );
              }).toList()..sort((a, b) {
                final modalityOrder = a.modality.compareTo(b.modality);
                if (modalityOrder != 0) {
                  return modalityOrder;
                }

                return a.description.compareTo(b.description);
              });

          return DicomStudy(
            studyInstanceUid: studyEntry.key,
            sourceDirectory: sourceLabel,
            patientName: representative.patientName,
            patientId: representative.patientId,
            studyDate: representative.studyDate,
            studyDescription: representative.studyDescription,
            series: series,
          );
        }).toList()..sort((a, b) {
          final dateOrder = b.studyDate.compareTo(a.studyDate);
          if (dateOrder != 0) {
            return dateOrder;
          }

          return a.patientName.compareTo(b.patientName);
        });

    return DicomStudyBundle(sourceDirectory: sourceLabel, studies: studies);
  }
}
