import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/addon.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/wow_installation.dart';
import '../../state/activity_log.dart';
import '../../state/nav_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../theme.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';

/// Picks a folder and adds the WoW clients found in it.
Future<void> addInstallationFromPicker(WidgetRef ref) async {
  final found = await pickInstallations(ref);
  if (found == null) return;
  final added = await ref
      .read(settingsProvider.notifier)
      .addInstallations(found);
  ref
      .read(activityProvider.notifier)
      .info(
        added == 0
            ? 'Installation ist bereits eingerichtet.'
            : '$added Installation(en) hinzugefügt',
      );
}

/// Lets the user choose a folder; `null` when cancelled or nothing found.
Future<List<WowInstallation>?> pickInstallations(WidgetRef ref) async {
  final dir = await FilePicker.getDirectoryPath(
    dialogTitle: 'World-of-Warcraft-Ordner wählen',
  );
  if (dir == null) return null;
  final found = await ref.read(installationDetectorProvider).fromUserPath(dir);
  if (found.isEmpty) {
    ref
        .read(activityProvider.notifier)
        .warning('In „$dir“ wurde kein WoW-Client gefunden.');
    return null;
  }
  return found;
}

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int _step = 1;
  bool _searching = true;
  final List<WowInstallation> _clients = [];
  final Set<String> _checked = {};

  @override
  void initState() {
    super.initState();
    final known = ref.read(settingsProvider).installations;
    _clients.addAll(known);
    _checked.addAll(known.map((i) => i.id));
    _detect();
  }

  Future<void> _detect() async {
    final found = await ref.read(installationDetectorProvider).detect();
    if (!mounted) return;
    setState(() {
      _add(found);
      _searching = false;
    });
  }

  void _add(List<WowInstallation> found) {
    for (final inst in found) {
      if (_clients.any((c) => c.id == inst.id)) continue;
      _clients.add(inst);
      _checked.add(inst.id);
    }
  }

  Future<void> _finish() async {
    final selected = _clients.where((c) => _checked.contains(c.id)).toList();
    // Saving the first installation swaps this page out, so grab the
    // navigator before the widget unmounts.
    final nav = ref.read(navProvider.notifier);
    await ref.read(settingsProvider.notifier).update((s) {
      final current = s.selectedInstallationId;
      return AppSettings.fromJson({
        ...s.toJson(),
        'installations': selected.map((i) => i.toJson()).toList(),
        'selectedInstallationId': selected.any((i) => i.id == current)
            ? current
            : selected.first.id,
      });
    });
    nav.go(AppView.installed);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final dataDir = ref.watch(storageProvider).rootPath;
    return Container(
      color: w.app,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: SingleChildScrollView(
        child: Container(
          width: 640,
          decoration: BoxDecoration(
            color: w.surface,
            border: Border.all(color: w.border),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A0F172A),
                blurRadius: 6,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$_step / 2',
                          style: WText.mono(
                            context,
                            color: WColors.orange,
                            weight: FontWeight.w700,
                          ).copyWith(letterSpacing: 1.1),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'EINRICHTUNG',
                          style: WText.caps(
                            w.muted,
                            spacing: 1.1,
                          ).copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _bar(WColors.orange)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _bar(_step == 2 ? WColors.orange : w.track),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: _step == 1
                    ? _stepClients(context)
                    : _stepSources(context),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: w.alt,
                  border: Border(top: BorderSide(color: w.border)),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _step == 1
                            ? '${_checked.length} von ${_clients.length} Installationen ausgewählt'
                            : 'Einstellungen werden in $dataDir gespeichert',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WText.muted(context),
                      ),
                    ),
                    if (_step == 2) ...[
                      WButton(
                        label: 'Zurück',
                        onPressed: () => setState(() => _step = 1),
                      ),
                      const SizedBox(width: 8),
                    ],
                    WButton(
                      kind: WButtonKind.primary,
                      label: _step == 1 ? 'Weiter' : 'Addons einlesen',
                      trailingIcon: Icons.arrow_forward_rounded,
                      onPressed: _checked.isEmpty
                          ? null
                          : () => _step == 1
                                ? setState(() => _step = 2)
                                : _finish(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(Color color) => Container(
    height: 3,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _heading(BuildContext context, String title, String text) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: WText.title(context)),
      const SizedBox(height: 4),
      Text(
        text,
        style: TextStyle(fontSize: 14, height: 1.65, color: context.w.muted),
      ),
    ],
  );

  Widget _stepClients(BuildContext context) {
    final w = context.w;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          _searching
              ? 'Suche WoW-Installationen …'
              : _clients.isEmpty
              ? 'Keine Installation gefunden'
              : 'WoW-Installationen gefunden',
          'Durchsucht wurden Standardpfade sowie Wine-, Lutris-, Bottles- und '
          'Steam-Proton-Prefixe. Wähle die Clients, deren Addons WoW Butler '
          'verwalten soll.',
        ),
        const SizedBox(height: 16),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: w.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searching)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: WProgress(value: null),
                ),
              for (final c in _clients)
                Hover(
                  onTap: () => setState(
                    () => _checked.contains(c.id)
                        ? _checked.remove(c.id)
                        : _checked.add(c.id),
                  ),
                  builder: (context, h) {
                    final on = _checked.contains(c.id);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: on ? w.sel : (h ? w.hover : Colors.transparent),
                        border: Border(bottom: BorderSide(color: w.border)),
                      ),
                      child: Row(
                        children: [
                          WCheckbox(checked: on, size: 18),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      c.label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: w.fg,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      c.gameVersion ?? c.flavor.label,
                                      style: WText.mono(context),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  c.clientPath,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WText.mono(context),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          WBadge(installVia(c), fg: w.fg2, bg: w.chip),
                        ],
                      ),
                    );
                  },
                ),
              Container(
                color: w.alt,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 16, color: w.fg2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Installation nicht dabei?',
                        style: TextStyle(fontSize: 13, color: w.fg2),
                      ),
                    ),
                    Hover(
                      onTap: () async {
                        final found = await pickInstallations(ref);
                        if (found != null && mounted) {
                          setState(() => _add(found));
                        }
                      },
                      builder: (context, h) => Text(
                        'Ordner manuell wählen',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: h ? WColors.blueHover : WColors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepSources(BuildContext context) {
    final w = context.w;
    final s = ref.watch(settingsProvider);
    final registry = ref.watch(sourcesProvider);
    final ctrl = ref.read(settingsProvider.notifier);

    Widget row(Widget left, Widget toggle, {bool last = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: w.border)),
      ),
      child: Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          toggle,
        ],
      ),
    );

    String hint(AddonSourceId id) =>
        registry[id].unavailableReason ??
        switch (id) {
          AddonSourceId.curseforge => 'Größter Addon-Katalog',
          AddonSourceId.wago => 'Wago Addons',
          AddonSourceId.wowup => 'GitHub-Addons aus dem WowUp Hub',
          AddonSourceId.tukui => 'ElvUI und Tukui direkt von tukui.org',
          AddonSourceId.github => 'Releases aus beliebigen Repositories',
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          context,
          'Quellen und Updates',
          'Alles lässt sich später unter Einstellungen ändern.',
        ),
        const SizedBox(height: 16),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: w.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (final id in s.sourcePriority)
                row(
                  Row(
                    children: [
                      Builder(
                        builder: (context) {
                          final c = sourceColors(context, id);
                          return WBadge(
                            id.label,
                            fg: c.fg,
                            bg: c.bg,
                            width: 84,
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          hint(id),
                          style: TextStyle(fontSize: 13, color: w.muted),
                        ),
                      ),
                    ],
                  ),
                  WToggle(
                    value: s.isSourceEnabled(id),
                    onChanged: (v) => ctrl.update(
                      (x) => x.copyWith(
                        disabledSources: v
                            ? ({...x.disabledSources}..remove(id))
                            : {...x.disabledSources, id},
                      ),
                    ),
                  ),
                ),
              row(
                _labelHint(
                  context,
                  'Addons automatisch aktualisieren',
                  'Beim Start und im gewählten Intervall',
                ),
                WToggle(
                  value: s.autoUpdate,
                  onChanged: (v) =>
                      ctrl.update((x) => x.copyWith(autoUpdate: v)),
                ),
              ),
              row(
                _labelHint(
                  context,
                  'WTF-Ordner vor Updates sichern',
                  'Addon-Einstellungen bleiben wiederherstellbar',
                ),
                WToggle(
                  value: s.backupBeforeUpdate,
                  onChanged: (v) =>
                      ctrl.update((x) => x.copyWith(backupBeforeUpdate: v)),
                ),
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _labelHint(BuildContext context, String label, String hint) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: context.w.fg,
        ),
      ),
      Text(hint, style: WText.muted(context)),
    ],
  );
}
