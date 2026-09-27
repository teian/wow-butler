import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/activity_log.dart';
import '../../state/addons_controller.dart';
import '../../state/settings_controller.dart';
import '../format.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';

/// 28px footer: client, counts, last check and auto-update state.
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inst = ref.watch(selectedInstallationProvider)!;
    final state = ref.watch(addonsProvider(inst.id));
    final settings = ref.watch(settingsProvider);
    final errors = ref.watch(
      activityProvider.select(
        (l) => l.where((e) => e.level == ActivityLevel.error).length,
      ),
    );
    final style = WText.mono(context);

    final String lastCheck;
    if (state.scanning) {
      lastCheck = 'Scanne AddOns …';
    } else if (state.checking) {
      lastCheck = 'Prüfe Updates …';
    } else {
      lastCheck =
          'Zuletzt geprüft ${state.lastChecked == null ? '–' : DateFormat.Hm('de').format(state.lastChecked!)}';
    }
    final interval = switch (settings.updateCheckMinutes) {
      0 => 'manuell',
      final m when m % 60 == 0 => 'alle ${m ~/ 60} h',
      final m => 'alle $m min',
    };

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.w.alt,
        border: Border(top: BorderSide(color: context.w.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: WColors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${inst.label} ${inst.gameVersion ?? inst.flavor.label}',
            style: style,
          ),
          const SizedBox(width: 16),
          Text(
            '${state.addons.length} Addons · ${state.updatable.length} Updates',
            style: style,
          ),
          const SizedBox(width: 16),
          Text(lastCheck, style: style),
          const Spacer(),
          Hover(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const ActivityDialog(),
            ),
            builder: (context, h) => Text(
              errors > 0 ? 'Protokoll · $errors Fehler' : 'Protokoll',
              style: style.copyWith(
                color: errors > 0 ? WColors.red : (h ? context.w.fg : null),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Auto-Update ${settings.autoUpdate ? 'AN · $interval' : 'AUS'}',
            style: style,
          ),
        ],
      ),
    );
  }
}

class ActivityDialog extends ConsumerWidget {
  const ActivityDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(activityProvider);
    return AlertDialog(
      title: const Text('Protokoll'),
      content: SizedBox(
        width: 680,
        height: 460,
        child: entries.isEmpty
            ? Center(
                child: Text(
                  'Noch keine Ereignisse.',
                  style: WText.muted(context, size: 13),
                ),
              )
            : ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) {
                  final e = entries[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          activityIcon(e.level),
                          size: 16,
                          color: activityColor(context, e.level),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelectableText(
                            e.message,
                            style: WText.body(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          formatDateTime(e.time),
                          style: WText.mono(context),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        WButton(label: 'Schließen', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}

IconData activityIcon(ActivityLevel level) => switch (level) {
  ActivityLevel.info => Icons.info_outline_rounded,
  ActivityLevel.success => Icons.check_circle_outline_rounded,
  ActivityLevel.warning => Icons.warning_amber_rounded,
  ActivityLevel.error => Icons.error_outline_rounded,
};

Color activityColor(BuildContext context, ActivityLevel level) =>
    switch (level) {
      ActivityLevel.info => WColors.blueLight,
      ActivityLevel.success => WColors.green,
      ActivityLevel.warning => WColors.amber,
      ActivityLevel.error => WColors.red,
    };
