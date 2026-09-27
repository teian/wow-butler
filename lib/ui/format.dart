import 'package:intl/intl.dart';

final _compact = NumberFormat.compact(locale: 'de');
final _date = DateFormat('dd.MM.yyyy', 'de');
final _dateTime = DateFormat('dd.MM.yyyy HH:mm', 'de');

String formatCount(int? n) => n == null ? '' : _compact.format(n);

String formatDate(DateTime? d) => d == null ? '–' : _date.format(d.toLocal());

String formatDateTime(DateTime? d) =>
    d == null ? '–' : _dateTime.format(d.toLocal());

String formatRelative(DateTime? d) {
  if (d == null) return '–';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'gerade eben';
  if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
  if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
  if (diff.inDays < 30) {
    return diff.inDays == 1 ? 'vor 1 Tag' : 'vor ${diff.inDays} Tagen';
  }
  return formatDate(d);
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// `110200` -> `11.2.0`, `11507` -> `1.15.7`.
String formatInterface(int interface) {
  final s = interface.toString();
  if (s.length < 5) return s;
  final major = int.parse(s.substring(0, s.length - 4));
  final minor = int.parse(s.substring(s.length - 4, s.length - 2));
  final patch = int.parse(s.substring(s.length - 2));
  return '$major.$minor.$patch';
}
