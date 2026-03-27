import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error }

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  IOSink? _sink;
  File? _logFile;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    try {
      final dir = await getApplicationSupportDirectory();
      final logsDir = Directory('${dir.path}${Platform.pathSeparator}logs');
      if (!logsDir.existsSync()) {
        logsDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      _logFile = File('${logsDir.path}${Platform.pathSeparator}app_$timestamp.log');
      _sink = _logFile!.openWrite(mode: FileMode.append);
      _initialized = true;

      info('AppLogger', 'Logger initialized — ${_logFile!.path}');
    } catch (e) {
      debugPrint('AppLogger init failed: $e');
    }
  }

  String get logFilePath => _logFile?.path ?? '';

  void _write(LogLevel level, String tag, String message,
      [Object? error, StackTrace? stack]) {
    final now = DateTime.now().toIso8601String();
    final label = level.name.toUpperCase().padRight(5);
    final line = StringBuffer('$now [$label] [$tag] $message');

    if (error != null) {
      line.write('\n  ERROR: $error');
    }
    if (stack != null) {
      final truncated = stack.toString().split('\n').take(8).join('\n  ');
      line.write('\n  STACK: $truncated');
    }

    final text = line.toString();
    _sink?.writeln(text);
    debugPrint(text);
  }

  void debug(String tag, String message) =>
      _write(LogLevel.debug, tag, message);

  void info(String tag, String message) =>
      _write(LogLevel.info, tag, message);

  void warn(String tag, String message, [Object? error, StackTrace? stack]) =>
      _write(LogLevel.warn, tag, message, error, stack);

  void error(String tag, String message, [Object? error, StackTrace? stack]) =>
      _write(LogLevel.error, tag, message, error, stack);

  Future<void> flush() async {
    await _sink?.flush();
  }

  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _initialized = false;
  }
}
