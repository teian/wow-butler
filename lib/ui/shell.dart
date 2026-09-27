import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../state/activity_log.dart';
import '../state/addons_controller.dart';
import '../state/nav_controller.dart';
import '../state/scheduler.dart';
import '../state/settings_controller.dart';
import 'chrome/sidebar.dart';
import 'chrome/status_bar.dart';
import 'chrome/title_bar.dart';
import 'chrome/update_queue_panel.dart';
import 'pages/addon_detail_page.dart';
import 'pages/backups_page.dart';
import 'pages/discover_page.dart';
import 'pages/my_addons_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/remote_detail_page.dart';
import 'pages/settings_page.dart';
import 'tokens.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(schedulerProvider);
    ref.listen(activityProvider, (previous, next) {
      if (next.isEmpty || identical(previous?.firstOrNull, next.first)) return;
      final entry = next.first;
      if (!entry.toast) return;
      messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  activityIcon(entry.level),
                  size: 16,
                  color: activityColor(context, entry.level),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(entry.message)),
              ],
            ),
            duration: Duration(
              seconds: entry.level == ActivityLevel.error ? 6 : 3,
            ),
          ),
        );
    });

    final nav = ref.watch(navProvider);
    final inst = ref.watch(selectedInstallationProvider);
    final onboarding = inst == null || nav.view == AppView.onboarding;

    String subtitle() {
      if (onboarding) return 'Einrichtung';
      final page = switch (nav.view) {
        AppView.installed => 'Meine Addons',
        AppView.browse || AppView.browseDetail => 'Entdecken',
        AppView.backups => 'Backups',
        AppView.settings => 'Einstellungen',
        AppView.onboarding => 'Einrichtung',
        AppView.detail =>
          ref.watch(
                addonsProvider(inst.id).select(
                  (s) => s.addons
                      .where((a) => a.id == nav.detailId)
                      .firstOrNull
                      ?.name,
                ),
              ) ??
              '',
      };
      return '${inst.label} — $page';
    }

    final index = switch (nav.view) {
      AppView.installed || AppView.onboarding => 0,
      AppView.detail => 1,
      AppView.browse => 2,
      AppView.backups => 3,
      AppView.settings => 4,
      AppView.browseDetail => 5,
    };

    return Scaffold(
      backgroundColor: context.w.app,
      body: Column(
        children: [
          TitleBar(subtitle: subtitle()),
          Expanded(
            child: onboarding
                ? const OnboardingPage()
                : Row(
                    children: [
                      const Sidebar(),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: IndexedStack(
                                index: index,
                                children: [
                                  const MyAddonsPage(),
                                  index == 1
                                      ? const AddonDetailPage()
                                      : const SizedBox.shrink(),
                                  const DiscoverPage(),
                                  const BackupsPage(),
                                  const SettingsPage(),
                                  index == 5
                                      ? const RemoteDetailPage()
                                      : const SizedBox.shrink(),
                                ],
                              ),
                            ),
                            const UpdateQueuePanel(),
                            const StatusBar(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
