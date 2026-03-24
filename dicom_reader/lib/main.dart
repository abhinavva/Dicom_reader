import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runZonedGuarded(
    () => runApp(const ProviderScope(child: DicomReaderApp())),
    (error, stack) {
      debugPrint('Uncaught error: $error\n$stack');
    },
  );
}
