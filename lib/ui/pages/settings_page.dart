import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/addon.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/wow_installation.dart';
import '../../state/activity_log.dart';
import '../../state/backup_controller.dart';
import '../../state/nav_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../format.dart';
import '../theme.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';
import 'onboarding_page.dart' show addInstallationFromPicker;

SettingsController _ctrl(WidgetRef ref) => ref.read(settingsProvider.notifier);

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Einstellungen', style: WText.title(context)),
              const SizedBox(height: 20),
              const _InstallationsCard(),
              const SizedBox(height: 20),
              const _UpdatesCard(),
              const SizedBox(height: 20),
              const _SourcesCard(),
              const SizedBox(height: 20),
              const _BackupCard(),
              const SizedBox(height: 20),
              const _SystemCard(),
              const SizedBox(height: 20),
              Text(
                'WoW Butler 1.0.0 · Flutter · ${Platform.operatingSystem}-${_arch()}',
                style: WText.mono(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _arch() {
    final v = Platform.version.toLowerCase();
    if (v.contains('arm64')) return 'arm64';
    return 'x64';
  }
}

// ---------------------------------------------------------------------------

class _InstallationsCard extends ConsumerStatefulWidget {
  const _InstallationsCard();

  @override
  ConsumerState<_InstallationsCard> createState() => _InstallationsCardState();
}

class _InstallationsCardState extends ConsumerState<_InstallationsCard> {
  bool _scanning = false;

  @override
  Widget build(BuildContext context) {
    final installations = ref.watch(
      settingsProvider.select((s) => s.installations),
    );
    final w = context.w;
    return SectionCard(
      title: 'WoW-Installationen',
      subtitle:
          'Wine-, Lutris-, Bottles- und Proton-Prefixe werden unterstützt',
      actions: [
        WButton(
          small: true,
          icon: Icons.inbox_outlined,
          label: _scanning ? 'Suche…' : 'Erneut suchen',
          onPressed: _scanning
              ? null
              : () async {
                  setState(() => _scanning = true);
                  try {
                    final n = await _ctrl(ref).detectInstallations();
                    ref
                        .read(activityProvider.notifier)
                        .info(
                          n == 0
                              ? 'Keine neuen Installationen gefunden'
                              : '$n Installation(en) hinzugefügt',
                        );
                  } finally {
                    if (mounted) setState(() => _scanning = false);
                  }
                },
        ),
        WButton(
          small: true,
          kind: WButtonKind.blue,
          label: 'Hinzufügen',
          onPressed: () => addInstallationFromPicker(ref),
        ),
      ],
      children: [
        for (final inst in installations)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: w.border)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inst.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: w.fg,
                        ),
                      ),
                      Text(
                        inst.gameVersion ?? inst.flavor.label,
                        style: WText.mono(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: PathChip(inst.clientPath)),
                const SizedBox(width: 14),
                WBadge(installVia(inst), fg: w.fg2, bg: w.chip),
                const SizedBox(width: 14),
                WIconButton(
                  icon: Icons.folder_outlined,
                  tooltip: 'Ordner öffnen',
                  onPressed: () => openFolder(inst.clientPath),
                ),
                WIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Entfernen',
                  onPressed: () => _remove(inst),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _remove(WowInstallation inst) async {
    final ok = await confirm(
      context,
      title: '${inst.label} entfernen?',
      message:
          'Die Installation wird nur aus WoW Butler entfernt. '
          'Addons und Einstellungen auf der Festplatte bleiben unverändert.',
      confirmLabel: 'Entfernen',
    );
    if (ok) await _ctrl(ref).removeInstallation(inst.id);
  }
}

// ---------------------------------------------------------------------------

class _UpdatesCard extends ConsumerWidget {
  const _UpdatesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final backupRoot = ref.watch(zipBackupRootProvider);
    return SectionCard(
      title: 'Updates',
      children: [
        SettingRow(
          label: 'Automatisch aktualisieren',
          hint: 'Gepinnte und ignorierte Addons ausgenommen',
          trailing: WToggle(
            value: s.autoUpdate,
            onChanged: (v) =>
                _ctrl(ref).update((x) => x.copyWith(autoUpdate: v)),
          ),
        ),
        SettingRow(
          label: 'Beim Start prüfen',
          hint: 'Sucht direkt nach dem Öffnen nach Updates',
          trailing: WToggle(
            value: s.checkOnStart,
            onChanged: (v) =>
                _ctrl(ref).update((x) => x.copyWith(checkOnStart: v)),
          ),
        ),
        SettingRow(
          label: 'WTF-Ordner vor Updates sichern',
          hint: 'Backup landet in $backupRoot',
          trailing: WToggle(
            value: s.backupBeforeUpdate,
            onChanged: (v) =>
                _ctrl(ref).update((x) => x.copyWith(backupBeforeUpdate: v)),
          ),
        ),
        SettingRow(
          label: 'Prüfintervall',
          hint: 'Solange WoW Butler läuft',
          trailing: WSegmented<int>(
            options: const [
              (60, '1 h'),
              (360, '6 h'),
              (1440, '24 h'),
              (0, 'Nie'),
            ],
            value: const [60, 360, 1440, 0].contains(s.updateCheckMinutes)
                ? s.updateCheckMinutes
                : 360,
            onChanged: (v) =>
                _ctrl(ref).update((x) => x.copyWith(updateCheckMinutes: v)),
          ),
        ),
        SettingRow(
          label: 'Standard-Kanal',
          hint: 'Pro Addon in der Detailansicht überschreibbar',
          trailing: WSegmented<ReleaseChannel>(
            options: [for (final c in ReleaseChannel.values) (c, c.label)],
            value: s.defaultChannel,
            onChanged: (v) =>
                _ctrl(ref).update((x) => x.copyWith(defaultChannel: v)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SourcesCard extends ConsumerWidget {
  const _SourcesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final registry = ref.watch(sourcesProvider);
    final w = context.w;

    String hint(AddonSourceId id) => switch (id) {
      AddonSourceId.curseforge => 'Eigener API-Key von console.curseforge.com',
      AddonSourceId.wago => 'Wago-API-Key für Addons',
      AddonSourceId.wowup => 'GitHub-Addons aus dem WowUp Hub',
      AddonSourceId.tukui => 'ElvUI und Tukui direkt von tukui.org',
      AddonSourceId.wowinterface =>
        'Addons von wowinterface.com über die Minion-API',
      AddonSourceId.github =>
        'Releases aus Repositories, Token hebt das Rate-Limit',
    };

    Widget? keyField(AddonSourceId id) => switch (id) {
      AddonSourceId.curseforge => _KeyField(
        hint: 'curseforge-api-key',
        value: s.curseforgeApiKey,
        onSaved: (v) =>
            _ctrl(ref).update((x) => x.copyWith(curseforgeApiKey: v)),
      ),
      AddonSourceId.wago => _KeyField(
        hint: 'wago-api-key',
        value: s.wagoApiKey,
        onSaved: (v) => _ctrl(ref).update((x) => x.copyWith(wagoApiKey: v)),
      ),
      AddonSourceId.github => _KeyField(
        hint: 'ghp_… (optional)',
        value: s.githubToken,
        onSaved: (v) => _ctrl(ref).update((x) => x.copyWith(githubToken: v)),
      ),
      _ => null,
    };

    return SectionCard(
      title: 'Quellen',
      subtitle: 'Reihenfolge = Priorität beim Zuordnen installierter Addons',
      children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: (child, _, _) =>
              Material(color: w.surface, elevation: 2, child: child),
          onReorderItem: (from, to) {
            final list = [...s.sourcePriority];
            list.insert(to, list.removeAt(from));
            _ctrl(ref).update((x) => x.copyWith(sourcePriority: list));
          },
          children: [
            for (final (i, id) in s.sourcePriority.indexed)
              Container(
                key: ValueKey(id),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: w.border)),
                ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 16,
                          color: w.strong,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final c = sourceColors(context, id);
                        return WBadge(id.label, fg: c.fg, bg: c.bg, width: 84);
                      },
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        registry[id].unavailableReason ?? hint(id),
                        style: TextStyle(
                          fontSize: 13,
                          color: registry[id].isAvailable
                              ? w.muted
                              : WColors.amber,
                        ),
                      ),
                    ),
                    if (keyField(id) case final field?) ...[
                      const SizedBox(width: 14),
                      SizedBox(width: 200, child: field),
                    ],
                    const SizedBox(width: 14),
                    WToggle(
                      value: s.isSourceEnabled(id),
                      onChanged: (v) => _ctrl(ref).update(
                        (x) => x.copyWith(
                          disabledSources: v
                              ? ({...x.disabledSources}..remove(id))
                              : {...x.disabledSources, id},
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Input that saves when submitted or when focus leaves, so the sources are
/// not rebuilt on every keystroke.
class _KeyField extends StatefulWidget {
  const _KeyField({
    required this.hint,
    required this.value,
    required this.onSaved,
    this.obscure = true,
  });

  final String hint;
  final String? value;
  final ValueChanged<String> onSaved;
  final bool obscure;

  @override
  State<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<_KeyField> {
  late final _controller = TextEditingController(text: widget.value ?? '');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  void _save() {
    final v = _controller.text.trim();
    if (v != (widget.value ?? '')) widget.onSaved(v);
  }

  @override
  void dispose() {
    // Keep a typed key that was never submitted (page closed mid-edit).
    _save();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WInput(
    controller: _controller,
    focusNode: _focus,
    hint: widget.hint,
    mono: true,
    obscure: widget.obscure && _controller.text.isNotEmpty,
    onSubmitted: (_) => _save(),
  );
}

// ---------------------------------------------------------------------------

class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final inst = ref.watch(selectedInstallationProvider);
    final zip = s.zipBackup;
    final git = s.gitBackup;
    final w = context.w;
    final last = inst == null
        ? null
        : ref.watch(zipBackupsProvider(inst.id)).value?.firstOrNull;
    final busy = ref.watch(backupProvider.select((b) => b.busy));

    void setZip(ZipBackupSettings Function(ZipBackupSettings) f) =>
        _ctrl(ref).update((x) => x.copyWith(zipBackup: f(x.zipBackup)));
    void setGit(GitBackupSettings Function(GitBackupSettings) f) =>
        _ctrl(ref).update((x) => x.copyWith(gitBackup: f(x.gitBackup)));

    Widget pick(String? path, String title, ValueChanged<String> onPicked) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: PathChip(path ?? 'Nicht festgelegt'),
            ),
            const SizedBox(width: 8),
            WButton(
              small: true,
              label: 'Wählen',
              onPressed: () async {
                final dir = await FilePicker.getDirectoryPath(
                  dialogTitle: title,
                );
                if (dir != null) onPicked(dir);
              },
            ),
          ],
        );

    return SectionCard(
      title: 'Backup',
      subtitle: 'ZIP-Archive in ein Verzeichnis deiner Wahl, versionierte Sicherung per Git',
      children: [
        SettingRow(
          label: 'ZIP-Backups automatisch erstellen',
          hint: 'Addons und WTF-Ordner in regelmäßigen Abständen',
          trailing: WToggle(
            value: zip.enabled,
            onChanged: zip.isConfigured
                ? (v) => setZip((z) => z.copyWith(enabled: v))
                : null,
          ),
        ),
        SettingRow(
          label: 'Zielordner',
          trailing: pick(
            zip.directory,
            'Zielordner für ZIP-Backups',
            (d) => setZip((z) => z.copyWith(directory: d, enabled: true)),
          ),
        ),
        SettingRow(
          label: 'Intervall und Aufbewahrung',
          hint: 'Ältere automatische Backups werden gelöscht',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WSegmented<int>(
                options: const [(6, '6 h'), (24, '24 h'), (168, 'Woche')],
                value: const [6, 24, 168].contains(zip.intervalHours)
                    ? zip.intervalHours
                    : 24,
                onChanged: (v) => setZip((z) => z.copyWith(intervalHours: v)),
              ),
              const SizedBox(width: 8),
              WSegmented<int>(
                options: const [(5, '5'), (10, '10'), (20, '20'), (0, 'Alle')],
                value: const [5, 10, 20, 0].contains(zip.retention)
                    ? zip.retention
                    : 10,
                onChanged: (v) => setZip((z) => z.copyWith(retention: v)),
              ),
            ],
          ),
        ),
        SettingRow(
          label: 'Umfang',
          trailing: WSegmented<bool>(
            options: const [(true, 'Addons + WTF'), (false, 'Nur WTF')],
            value: zip.includeAddons,
            onChanged: (v) =>
                setZip((z) => z.copyWith(includeAddons: v, includeWtf: true)),
          ),
        ),
        SettingRow(
          label: 'Git-Backups automatisch erstellen',
          hint: 'Jede Sicherung ist ein Commit mit vollständiger Historie',
          trailing: WToggle(
            value: git.enabled,
            onChanged: git.isConfigured
                ? (v) => setGit((g) => g.copyWith(enabled: v))
                : null,
          ),
        ),
        SettingRow(
          label: 'Repository',
          trailing: pick(
            git.repoPath,
            'Ordner für das Backup-Repository',
            (d) => setGit((g) => g.copyWith(repoPath: d, enabled: true)),
          ),
        ),
        SettingRow(
          label: 'Remote und Branch',
          hint: 'Zugangsdaten kommen aus deiner git-Konfiguration (SSH, Credential Helper)',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 240,
                child: _KeyField(
                  hint: 'git@github.com:name/wow-backup.git',
                  value: git.remoteUrl,
                  obscure: false,
                  onSaved: (v) => setGit((g) => g.copyWith(remoteUrl: v)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: _KeyField(
                  hint: 'main',
                  value: git.branch,
                  obscure: false,
                  onSaved: (v) =>
                      setGit((g) => g.copyWith(branch: v.isEmpty ? 'main' : v)),
                ),
              ),
            ],
          ),
        ),
        SettingRow(
          label: 'Addon-Dateien versionieren',
          hint: 'Aus: nur die Addon-Liste – Addons lassen sich daraus neu installieren',
          trailing: WToggle(
            value: git.includeAddonFiles,
            onChanged: (v) => setGit((g) => g.copyWith(includeAddonFiles: v)),
          ),
        ),
        SettingRow(
          label: 'Nach jedem Backup pushen',
          trailing: WToggle(
            value: git.autoPush,
            onChanged: (git.remoteUrl?.isNotEmpty ?? false)
                ? (v) => setGit((g) => g.copyWith(autoPush: v))
                : null,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: w.alt,
            border: Border(top: BorderSide(color: w.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.archive_outlined, size: 18, color: w.muted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Letztes Backup',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: w.fg,
                      ),
                    ),
                    Text(
                      last == null
                          ? 'Noch keins für diese Installation'
                          : '${last.fileName} · ${formatBytes(last.sizeBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WText.mono(context),
                    ),
                  ],
                ),
              ),
              WButton(
                small: true,
                label: 'Wiederherstellen',
                onPressed: () =>
                    ref.read(navProvider.notifier).go(AppView.backups),
              ),
              const SizedBox(width: 8),
              WButton(
                small: true,
                kind: WButtonKind.blue,
                label: busy ? 'Sichert…' : 'Backup erstellen',
                onPressed: busy || inst == null
                    ? null
                    : () async {
                        final b = ref.read(backupProvider.notifier);
                        await b.runZip(only: [inst]);
                        if (git.isConfigured) await b.runGit(only: [inst]);
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SystemCard extends ConsumerWidget {
  const _SystemCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final dataDir = ref.watch(storageProvider).rootPath;
    return SectionCard(
      title: 'System',
      children: [
        SettingRow(
          label: 'Darstellung',
          trailing: WSegmented<AppThemeMode>(
            options: const [
              (AppThemeMode.light, 'Hell'),
              (AppThemeMode.dark, 'Dunkel'),
              (AppThemeMode.system, 'System'),
            ],
            value: mode,
            onChanged: (m) =>
                _ctrl(ref).update((x) => x.copyWith(themeMode: m)),
          ),
        ),
        SettingRow(
          label: 'Datenordner',
          hint: dataDir,
          trailing: WButton(
            small: true,
            label: 'Öffnen',
            onPressed: () => openFolder(dataDir),
          ),
        ),
        SettingRow(
          label: 'Einrichtung erneut starten',
          hint: 'Installationen neu suchen und Quellen wählen',
          trailing: WButton(
            small: true,
            label: 'Starten',
            onPressed: () =>
                ref.read(navProvider.notifier).go(AppView.onboarding),
          ),
        ),
      ],
    );
  }
}
