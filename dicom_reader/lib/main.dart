import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/app_logger.dart';

void main() async {
  await AppLogger.instance.init();

  final log = AppLogger.instance;
  log.info('Main', 'Application starting');

  FlutterError.onError = (details) {
    log.error(
      'FlutterError',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
    FlutterError.presentError(details);
  };

  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(const ProviderScope(child: DicomReaderApp()));
    },
    (error, stack) {
      log.error('Zone', 'Uncaught error', error, stack);
    },
  );
}
