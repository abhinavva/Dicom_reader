import 'package:dicom_reader/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows worklist with icon-only local loading actions', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: DicomReaderApp()));

    expect(find.text('Public DICOM Worklist'), findsOneWidget);
    expect(find.byTooltip('Open DICOM files'), findsOneWidget);
    expect(find.byTooltip('Open DICOM folder'), findsOneWidget);
    expect(find.text('Load Folder'), findsNothing);
    expect(find.text('Open Files'), findsNothing);
  });
}
