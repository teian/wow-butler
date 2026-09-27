import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/wow_installation.dart';
import '../../services/backup/git_backup_service.dart';
import '../../services/backup/zip_backup_service.dart';
import '../../state/addons_controller.dart';
import '../../state/backup_controller.dart';
import '../../state/nav_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../format.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';

class BackupsPage extends ConsumerWidget {
  const BackupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inst = ref.watch(selectedInstallationProvider)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Backups', style: WText.title(context)),
              const SizedBox(height: 4),
              Text(
                '${inst.label} · Vor jeder Wiederherstellung wird der aktuelle Stand automatisch gesichert.',
                style: WText.muted(context, size: 13),
              ),
              const SizedBox(height: 20),
              const _ZipCard(),
              const SizedBox(height: 20),
              const _GitCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.icon,
    required this.title,
    required this.meta,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String meta;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: w.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: w.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: w.fg,
                  ),
                ),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WText.mono(context),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

Widget _empty(BuildContext context, String text) => Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    border: Border(top: BorderSide(color: context.w.border)),
  ),
  child: Text(text, style: WText.muted(context, size: 13)),
);

class _ZipCard extends ConsumerWidget {
  const _ZipCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inst = ref.watch(selectedInstallationProvider)!;
    final root = ref.watch(zipBackupRootProvider);
    final backup = ref.watch(backupProvider);
    final list = ref.watch(zipBackupsProvider(inst.id));
    final ctrl = ref.read(backupProvider.notifier);

    return SectionCard(
      title: 'ZIP-Archive',
      subtitle: root,
      actions: [
        WButton(
          small: true,
          label: 'Ordner öffnen',
          onPressed: () async {
            await Directory(root).create(recursive: true);
            await openFolder(root);
          },
        ),
        WButton(
          small: true,
          kind: WButtonKind.blue,
          label: backup.zipRunning ? 'Sichert…' : 'Backup erstellen',
          onPressed: backup.busy ? null : () => ctrl.runZip(only: [inst]),
        ),
      ],
      children: list.when(
        loading: () => [
          const Padding(
            padding: EdgeInsets.all(20),
            child: WProgress(value: null),
          ),
        ],
        error: (e, _) => [_empty(context, '$e')],
        data: (items) => items.isEmpty
            ? [
                _empty(
                  context,
                  'Noch keine ZIP-Backups für diese Installation.',
                ),
              ]
            : [
                for (final b in items.take(50))
                  _ListRow(
                    icon: Icons.archive_outlined,
                    title: formatDateTime(b.createdAt),
                    meta: '${b.fileName} · ${formatBytes(b.sizeBytes)}',
                    actions: [
                      WButton(
                        small: true,
                        label: 'Wiederherstellen',
                        onPressed: backup.busy
                            ? null
                            : () => _restoreZip(context, ref, inst, b),
                      ),
                      const SizedBox(width: 4),
                      WIconButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Löschen',
                        onPressed: () async {
                          final ok = await confirm(
                            context,
                            title: 'Backup löschen?',
                            message: b.fileName,
                            confirmLabel: 'Löschen',
                            destructive: true,
                          );
                          if (!ok) return;
                          await File(b.path).delete();
                          ref.invalidate(zipBackupsProvider(inst.id));
                        },
                      ),
                    ],
                  ),
              ],
      ),
    );
  }

  Future<void> _restoreZip(
    BuildContext context,
    WidgetRef ref,
    WowInstallation inst,
    ZipBackup b,
  ) async {
    final scope = await _askScope(
      context,
      'Backup vom ${formatDateTime(b.createdAt)} wiederherstellen?',
    );
    if (scope == null) return;
    await ref.read(backupProvider.notifier).restoreZip(inst, b, scope);
  }
}

class _GitCard extends ConsumerWidget {
  const _GitCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inst = ref.watch(selectedInstallationProvider)!;
    final cfg = ref.watch(settingsProvider.select((s) => s.gitBackup));
    final backup = ref.watch(backupProvider);
    final gitVersion = ref.watch(gitVersionProvider);
    final ctrl = ref.read(backupProvider.notifier);

    if (gitVersion.hasValue && gitVersion.value == null) {
      return SectionCard(
        title: 'Git-Historie',
        children: [
          _empty(
            context,
            'git wurde nicht gefunden. Installiere git, um versionierte Backups zu nutzen.',
          ),
        ],
      );
    }
    if (!cfg.isConfigured) {
      return SectionCard(
        title: 'Git-Historie',
        subtitle: 'Noch kein Repository eingerichtet',
        actions: [
          WButton(
            small: true,
            kind: WButtonKind.blue,
            label: 'In Einstellungen einrichten',
            onPressed: () =>
                ref.read(navProvider.notifier).go(AppView.settings),
          ),
        ],
      );
    }

    final history = ref.watch(gitHistoryProvider(inst.id));
    final hasRemote = cfg.remoteUrl?.trim().isNotEmpty ?? false;
    return SectionCard(
      title: 'Git-Historie',
      subtitle: [
        cfg.repoPath!,
        if (hasRemote) '→ ${cfg.remoteUrl} (${cfg.branch})',
        ?gitVersion.value,
      ].join('  ·  '),
      actions: [
        if (hasRemote)
          WButton(
            small: true,
            icon: Icons.cloud_upload_outlined,
            label: 'Push',
            onPressed: backup.busy ? null : ctrl.push,
          ),
        WButton(
          small: true,
          kind: WButtonKind.blue,
          label: backup.gitRunning ? 'Committet…' : 'Commit erstellen',
          onPressed: backup.busy ? null : () => ctrl.runGit(only: [inst]),
        ),
      ],
      children: history.when(
        loading: () => [
          const Padding(
            padding: EdgeInsets.all(20),
            child: WProgress(value: null),
          ),
        ],
        error: (e, _) => [_empty(context, '$e')],
        data: (commits) => commits.isEmpty
            ? [_empty(context, 'Noch keine Commits für diese Installation.')]
            : [
                for (final c in commits.take(50))
                  _ListRow(
                    icon: Icons.commit_rounded,
                    title: c.message,
                    meta: '${formatDateTime(c.date)} · ${c.shortHash}',
                    actions: [
                      WIconButton(
                        icon: Icons.playlist_add_rounded,
                        tooltip:
                            'Fehlende Addons aus diesem Stand installieren',
                        onPressed: () =>
                            _installFromManifest(context, ref, inst, c),
                      ),
                      const SizedBox(width: 4),
                      WButton(
                        small: true,
                        label: 'Wiederherstellen',
                        onPressed: backup.busy
                            ? null
                            : () => _restoreGit(context, ref, inst, c),
                      ),
                    ],
                  ),
              ],
      ),
    );
  }

  Future<void> _restoreGit(
    BuildContext context,
    WidgetRef ref,
    WowInstallation inst,
    GitCommit c,
  ) async {
    final scope = await _askScope(
      context,
      'Stand vom ${formatDateTime(c.date)} (${c.shortHash}) wiederherstellen?',
    );
    if (scope == null) return;
    await ref.read(backupProvider.notifier).restoreGit(inst, c, scope);
  }

  Future<void> _installFromManifest(
    BuildContext context,
    WidgetRef ref,
    WowInstallation inst,
    GitCommit c,
  ) async {
    final cfg = ref.read(settingsProvider).gitBackup;
    final manifest = await ref
        .read(gitBackupServiceProvider)
        .manifestAt(cfg, inst, c.hash);
    if (manifest == null || !context.mounted) return;
    final current = ref.read(addonsProvider(inst.id)).addons;
    final missing = manifest
        .where(
          (m) => m.isManaged && !current.any((a) => a.remoteKey == m.remoteKey),
        )
        .toList();
    if (missing.isEmpty) {
      await confirm(
        context,
        title: 'Nichts zu tun',
        message: 'Alle Addons aus diesem Stand sind bereits installiert.',
      );
      return;
    }
    final ok = await confirm(
      context,
      title: '${missing.length} Addons installieren?',
      message: missing.map((m) => '• ${m.name}').join('\n'),
      confirmLabel: 'Installieren',
    );
    if (!ok) return;
    await ref
        .read(addonsProvider(inst.id).notifier)
        .installFromManifest(missing);
  }
}

Future<BackupScope?> _askScope(BuildContext context, String title) {
  var addons = true;
  var wtf = true;
  return showDialog<BackupScope>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Widget option(
          String label,
          String hint,
          bool value,
          ValueChanged<bool> onChanged,
        ) => Hover(
          onTap: () => onChanged(!value),
          builder: (context, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                WCheckbox(checked: value, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
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
                  ),
                ),
              ],
            ),
          ),
        );
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                option(
                  'Addons',
                  'Interface/AddOns',
                  addons,
                  (v) => setState(() => addons = v),
                ),
                option(
                  'Einstellungen',
                  'WTF – Tastenbelegung, Makros, SavedVariables',
                  wtf,
                  (v) => setState(() => wtf = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Das Spiel sollte dabei geschlossen sein. Der aktuelle Stand wird vorher gesichert.',
                  style: WText.muted(context, size: 13),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            WButton(
              label: 'Abbrechen',
              onPressed: () => Navigator.pop(context),
            ),
            WButton(
              kind: WButtonKind.blue,
              label: 'Wiederherstellen',
              onPressed: addons || wtf
                  ? () => Navigator.pop(
                      context,
                      BackupScope(addons: addons, wtf: wtf),
                    )
                  : null,
            ),
          ],
        );
      },
    ),
  );
}
