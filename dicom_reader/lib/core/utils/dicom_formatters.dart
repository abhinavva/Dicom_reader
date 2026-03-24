import 'package:intl/intl.dart';

String formatDicomDate(String rawDate) {
  if (rawDate.isEmpty || rawDate.length != 8) {
    return rawDate;
  }

  try {
    final parsed = DateFormat('yyyyMMdd').parseUtc(rawDate);
    return DateFormat('dd MMM yyyy').format(parsed.toLocal());
  } catch (_) {
    return rawDate;
  }
}

String formatDicomName(String rawName) {
  if (rawName.isEmpty) {
    return 'Unknown Patient';
  }

  return rawName
      .split('^')
      .where((part) => part.trim().isNotEmpty)
      .map((part) {
        final lower = part.toLowerCase();
        return lower[0].toUpperCase() + lower.substring(1);
      })
      .join(' ');
}

String formatViewportZoom(double zoom) {
  return '${(zoom * 100).toStringAsFixed(0)}%';
}

String formatWindowLevel(double? windowWidth, double? windowCenter) {
  if (windowWidth == null || windowCenter == null) {
    return 'WL -- / WW --';
  }

  return 'WL ${windowCenter.toStringAsFixed(0)} / WW ${windowWidth.toStringAsFixed(0)}';
}

String compactFileCount(int count) {
  return count == 1 ? '1 slice' : '$count slices';
}
