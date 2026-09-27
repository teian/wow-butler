import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ActivityLevel { info, success, warning, error }

class ActivityEntry {
  ActivityEntry(this.message, this.level, {this.toast = true})
    : time = DateTime.now();

  final String message;
  final ActivityLevel level;
  final DateTime time;

  /// Whether the UI should surface the entry as a snackbar.
  final bool toast;
}

final activityProvider = NotifierProvider<ActivityLog, List<ActivityEntry>>(
  ActivityLog.new,
);

/// Recent events (updates, backups, errors) shown in the activity panel.
class ActivityLog extends Notifier<List<ActivityEntry>> {
  static const _max = 200;

  @override
  List<ActivityEntry> build() => const [];

  void add(
    String message, {
    ActivityLevel level = ActivityLevel.info,
    bool toast = true,
  }) {
    final next = [ActivityEntry(message, level, toast: toast), ...state];
    state = next.length > _max ? next.sublist(0, _max) : next;
  }

  void info(String m, {bool toast = true}) => add(m, toast: toast);
  void success(String m, {bool toast = true}) =>
      add(m, level: ActivityLevel.success, toast: toast);
  void warning(String m, {bool toast = true}) =>
      add(m, level: ActivityLevel.warning, toast: toast);
  void error(String m) => add(m, level: ActivityLevel.error);
}
