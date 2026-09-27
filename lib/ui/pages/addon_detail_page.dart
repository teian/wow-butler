import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/addon.dart';
import '../../core/models/game_flavor.dart';
import '../../core/models/wow_installation.dart';
import '../../state/addons_controller.dart';
import '../../state/detail_providers.dart';
import '../../state/nav_controller.dart';
import '../../state/settings_controller.dart';
import '../format.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';
import 'my_addons_page.dart' show gameVersionOf;

class AddonDetailPage extends ConsumerWidget {
  const AddonDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inst = ref.watch(selectedInstallationProvider)!;
    final nav = ref.watch(navProvider);
    final addon = ref.watch(
      addonsProvider(
        inst.id,
      ).select((s) => s.addons.where((a) => a.id == nav.detailId).firstOrNull),
    );
    final queued = ref.watch(
      addonsProvider(inst.id)
          .select((s) => nav.detailId == null ? null : s.queued(nav.detailId!)),
    );
    final ctrl = ref.read(addonsProvider(inst.id).notifier);
    final w = context.w;

    if (addon == null) {
      return Center(
        child: Text(
          'Addon nicht mehr vorhanden.',
          style: WText.muted(context, size: 13),
        ),
      );
    }
    final key = (installationId: inst.id, addonId: addon.id);
    final status = StatusPill.of(context, addon);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Hover(
              onTap: () => ref.read(navProvider.notifier).go(AppView.installed),
              builder: (context, h) {
                final c = h ? w.fg : w.muted;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left_rounded, size: 18, color: c),
                    const SizedBox(width: 2),
                    Text(
                      'Meine Addons',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              InitialsTile(name: addon.name, url: addon.thumbnailUrl, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(addon.name, style: WText.title(context)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (addon.author != null) ...[
                          Flexible(
                            child: Text(
                              addon.author!,
                              overflow: TextOverflow.ellipsis,
                              style: WText.muted(context, size: 13),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        SourceBadge(addon.source),
                        const SizedBox(width: 10),
                        status,
                      ],
                    ),
                  ],
                ),
              ),
              if (addon.websiteUrl != null) ...[
                const SizedBox(width: 16),
                WButton(
                  label: 'Auf ${addon.source?.label ?? 'Website'} öffnen',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => openUrl(addon.websiteUrl),
                ),
              ],
              if (addon.hasUpdate && queued == null) ...[
                const SizedBox(width: 8),
                WButton(
                  kind: WButtonKind.primary,
                  icon: Icons.download_rounded,
                  label:
                      'Auf ${_short(addon.latestRelease!.version)} aktualisieren',
                  onPressed: () => ctrl.update(addon),
                ),
              ],
              if (queued != null) ...[
                const SizedBox(width: 16),
                SizedBox(width: 160, child: WProgress(value: queued.progress)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: WCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Tabs(managed: addon.isManaged, current: nav.tab),
                      switch (addon.isManaged ? nav.tab : DetailTab.overview) {
                        DetailTab.overview => _Overview(
                          inst: inst,
                          addon: addon,
                          addonKey: key,
                        ),
                        DetailTab.changelog => _Changelog(addonKey: key),
                        DetailTab.versions => _Versions(
                          inst: inst,
                          addon: addon,
                          addonKey: key,
                        ),
                      },
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 320,
                child: _Manage(inst: inst, addon: addon),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _short(String version) =>
    version.length > 16 ? version.substring(version.length - 11) : version;

class _Tabs extends ConsumerWidget {
  const _Tabs({required this.managed, required this.current});

  final bool managed;
  final DetailTab current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final tabs = [
      (DetailTab.overview, 'Übersicht'),
      if (managed) (DetailTab.changelog, 'Changelog'),
      if (managed) (DetailTab.versions, 'Versionen'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: w.border)),
      ),
      child: Row(
        children: [
          for (final (tab, label) in tabs)
            Hover(
              onTap: () => ref.read(navProvider.notifier).tab(tab),
              builder: (context, h) {
                final on =
                    tab == current || (!managed && tab == DetailTab.overview);
                return Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: on ? WColors.orange : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on || h ? w.fg : w.muted,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({
    required this.inst,
    required this.addon,
    required this.addonKey,
  });

  final WowInstallation inst;
  final InstalledAddon addon;
  final AddonKey addonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final remote = ref.watch(addonRemoteProvider(addonKey));
    final allAddons = ref.watch(
      addonsProvider(inst.id).select((s) => s.addons),
    );
    final deps = [
      for (final id in addon.latestRelease?.dependencies ?? const <String>[])
        allAddons
                .where((a) => a.source == addon.source && a.externalId == id)
                .firstOrNull
                ?.name ??
            '#$id',
    ];
    final downloads = remote.value?.downloadCount;
    final stats = [
      ('Installiert', _short(addon.installedVersion ?? '—')),
      (
        'Downloads',
        downloads == null
            ? (remote.isLoading ? '…' : '—')
            : formatCount(downloads),
      ),
      ('Spielversion', gameVersionOf(addon, inst)),
    ];

    Widget caps(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: WText.caps(w.muted)),
    );

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            addon.summary ?? 'Keine Beschreibung vorhanden.',
            style: TextStyle(fontSize: 14, height: 1.65, color: w.fg2),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: w.border,
              border: Border.all(color: w.border),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                for (final (i, (k, v)) in stats.indexed) ...[
                  if (i > 0) const SizedBox(width: 1),
                  Expanded(
                    child: Container(
                      color: w.surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            k.toUpperCase(),
                            style: WText.caps(w.muted, spacing: 0.8),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            v,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WText.mono(
                              context,
                              size: 14,
                              color: w.fg,
                              weight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          caps('ORDNER IN INTERFACE/ADDONS'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in addon.folders)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: w.chip,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    f,
                    style: WText.mono(context, size: 12, color: w.fg2),
                  ),
                ),
            ],
          ),
          if (deps.isNotEmpty) ...[
            const SizedBox(height: 16),
            caps('ABHÄNGIGKEITEN'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in deps)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: w.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: w.fg2,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Changelog extends ConsumerWidget {
  const _Changelog({required this.addonKey});

  final AddonKey addonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final entries = ref.watch(changelogProvider(addonKey));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: entries.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: WProgress(value: null),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('$e', style: WText.muted(context, size: 13)),
        ),
        data: (list) => list.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Kein Changelog verfügbar.',
                  style: WText.muted(context, size: 13),
                ),
              )
            : Column(
                children: [
                  for (final (i, e) in list.indexed)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        border: i == list.length - 1
                            ? null
                            : Border(bottom: BorderSide(color: w.border)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  e.version,
                                  overflow: TextOverflow.ellipsis,
                                  style: WText.mono(
                                    context,
                                    size: 13,
                                    color: w.fg,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                formatDate(e.date),
                                style: WText.muted(context),
                              ),
                              if (e.isNew) ...[
                                const SizedBox(width: 10),
                                WBadge(
                                  'NEU',
                                  fg: WColors.orange,
                                  bg: WColors.orange.withValues(alpha: 0.12),
                                ),
                              ],
                              if (e.installed) ...[
                                const SizedBox(width: 10),
                                WBadge(
                                  'INSTALLIERT',
                                  fg: WColors.green,
                                  bg: WColors.green.withValues(alpha: 0.14),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (e.lines.isEmpty)
                            Text(
                              'Keine Release-Notes.',
                              style: WText.muted(context, size: 13),
                            )
                          else
                            for (final line in e.lines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '–',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: w.muted,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        line,
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.55,
                                          color: w.fg2,
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
              ),
      ),
    );
  }
}

class _Versions extends ConsumerWidget {
  const _Versions({
    required this.inst,
    required this.addon,
    required this.addonKey,
  });

  final WowInstallation inst;
  final InstalledAddon addon;
  final AddonKey addonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final remote = ref.watch(addonRemoteProvider(addonKey));
    final installing = ref.watch(
      addonsProvider(inst.id)
          .select((s) => s.installing.containsKey(remote.value?.key)),
    );

    Widget row(List<Widget> cells, {bool header = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: w.border)),
      ),
      child: DefaultTextStyle.merge(
        style: header ? WText.caps(w.muted, spacing: 0.8) : null,
        child: Row(
          children: [
            Expanded(flex: 16, child: cells[0]),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: Align(alignment: Alignment.centerLeft, child: cells[1]),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 90, child: cells[2]),
            const SizedBox(width: 12),
            SizedBox(width: 70, child: cells[3]),
            const SizedBox(width: 12),
            SizedBox(
              width: 100,
              child: Align(alignment: Alignment.centerRight, child: cells[4]),
            ),
          ],
        ),
      ),
    );

    return remote.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: WProgress(value: null),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text('$e', style: WText.muted(context, size: 13)),
      ),
      data: (r) {
        if (r == null || r.releases.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Keine Versionen für ${inst.flavor.label} gefunden.',
              style: WText.muted(context, size: 13),
            ),
          );
        }
        final releases = [...r.releases]
          ..sort(
            (a, b) => (b.releasedAt ?? DateTime(0)).compareTo(
              a.releasedAt ?? DateTime(0),
            ),
          );
        return Column(
          children: [
            row(const [
              Text('VERSION'),
              Text('KANAL'),
              Text('DATUM'),
              Text('SPIEL'),
              SizedBox.shrink(),
            ], header: true),
            for (final rel in releases)
              row([
                Text(
                  rel.version,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WText.mono(context, size: 12, color: w.fg),
                ),
                ChannelPill(rel.channel),
                Text(
                  formatDate(rel.releasedAt),
                  style: WText.mono(context, size: 12),
                ),
                Text(
                  _releaseGame(rel, inst),
                  style: WText.mono(context, size: 12),
                ),
                rel.id == addon.installedReleaseId
                    ? const Text(
                        'Installiert',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: WColors.green,
                        ),
                      )
                    : Hover(
                        onTap: installing
                            ? null
                            : () => ref
                                  .read(addonsProvider(inst.id).notifier)
                                  .install(r, rel, channel: addon.channel),
                        builder: (context, h) => Text(
                          'Installieren',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: h ? WColors.blueHover : WColors.blue,
                          ),
                        ),
                      ),
              ]),
          ],
        );
      },
    );
  }

  String _releaseGame(AddonRelease r, WowInstallation inst) {
    final i =
        r.interfaces
            .where((i) => GameFlavor.fromInterface(i) == inst.flavor)
            .firstOrNull ??
        r.interfaces.firstOrNull;
    if (i != null) return formatInterface(i);
    return inst.gameVersion?.split('.').take(3).join('.') ?? '—';
  }
}

class _Manage extends ConsumerWidget {
  const _Manage({required this.inst, required this.addon});

  final WowInstallation inst;
  final InstalledAddon addon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final ctrl = ref.read(addonsProvider(inst.id).notifier);
    final globalAuto = ref.watch(settingsProvider.select((s) => s.autoUpdate));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Text('VERWALTUNG', style: WText.caps(w.muted)),
              ),
              if (addon.isManaged)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Release-Kanal',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: w.fg,
                        ),
                      ),
                      const SizedBox(height: 6),
                      WSegmented<ReleaseChannel>(
                        expand: true,
                        options: [
                          for (final c in ReleaseChannel.values) (c, c.label),
                        ],
                        value: addon.channel,
                        onChanged: (c) => ctrl.setChannel(addon, c),
                      ),
                    ],
                  ),
                ),
              if (addon.isManaged)
                _ToggleRow(
                  label: 'Automatisch aktualisieren',
                  hint: globalAuto
                      ? 'Folgt der globalen Einstellung'
                      : 'Global deaktiviert',
                  value: addon.autoUpdate,
                  onChanged: (v) => ctrl.setAutoUpdate(addon, v),
                ),
              if (addon.isManaged)
                _ToggleRow(
                  label: 'Version pinnen',
                  hint: 'Bleibt auf ${_short(addon.installedVersion ?? '—')}',
                  value: addon.pinned,
                  onChanged: (v) => ctrl.setPinned([addon.id], v),
                ),
              _ToggleRow(
                label: 'Ignorieren',
                hint: 'Keine Update-Hinweise',
                value: addon.ignored,
                onChanged: (v) => ctrl.setIgnored([addon.id], v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            if (addon.isManaged) ...[
              Expanded(
                child: WButton(
                  label: 'Neu installieren',
                  expand: true,
                  onPressed: () => ctrl.reinstall(addon),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: WButton(
                label: 'Deinstallieren',
                icon: Icons.delete_outline_rounded,
                kind: WButtonKind.danger,
                expand: true,
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: '${addon.name} deinstallieren?',
                    message:
                        'Folgende Ordner werden gelöscht:\n\n'
                        '${addon.folders.map((f) => '• $f').join('\n')}',
                    confirmLabel: 'Deinstallieren',
                    destructive: true,
                  );
                  if (!ok) return;
                  await ctrl.uninstall(addon);
                  ref.read(navProvider.notifier).go(AppView.installed);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: w.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: w.fg,
                  ),
                ),
                Text(hint, style: WText.muted(context)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          WToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
