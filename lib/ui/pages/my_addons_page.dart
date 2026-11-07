import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/addon.dart';
import '../../core/models/game_flavor.dart';
import '../../core/models/wow_installation.dart';
import '../../state/addons_controller.dart';
import '../../state/nav_controller.dart';
import '../../state/settings_controller.dart';
import '../format.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';

enum _Filter { all, updates, pinned, ignored, external, websiteOnly }

/// Column layout of the addon table (28px | 2.4fr | 1.6fr | 104 | 72 | 104 | 118).
class _Cols {
  static const gap = 12.0;
  static const check = 28.0;
  static const source = 104.0;
  static const game = 72.0;
  static const status = 104.0;
  static const action = 118.0;

  static Widget row(List<Widget> cells) => Row(
    children: [
      SizedBox(
        width: check,
        child: Align(alignment: Alignment.centerLeft, child: cells[0]),
      ),
      const SizedBox(width: gap),
      Expanded(flex: 24, child: cells[1]),
      const SizedBox(width: gap),
      Expanded(flex: 16, child: cells[2]),
      const SizedBox(width: gap),
      SizedBox(
        width: source,
        child: Align(alignment: Alignment.centerLeft, child: cells[3]),
      ),
      const SizedBox(width: gap),
      SizedBox(width: game, child: cells[4]),
      const SizedBox(width: gap),
      SizedBox(
        width: status,
        child: Align(alignment: Alignment.centerLeft, child: cells[5]),
      ),
      const SizedBox(width: gap),
      SizedBox(
        width: action,
        child: Align(alignment: Alignment.centerRight, child: cells[6]),
      ),
    ],
  );
}

class MyAddonsPage extends ConsumerStatefulWidget {
  const MyAddonsPage({super.key});

  @override
  ConsumerState<MyAddonsPage> createState() => _MyAddonsPageState();
}

class _MyAddonsPageState extends ConsumerState<MyAddonsPage> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  final Set<String> _selected = {};
  String? _installationId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static bool _isExternal(InstalledAddon a) => !a.isManaged && a.external;

  static const _optionalFilters = {_Filter.external, _Filter.websiteOnly};

  bool _matches(InstalledAddon a) {
    final ok = switch (_filter) {
      _Filter.all => true,
      _Filter.updates => a.hasUpdate,
      _Filter.pinned => a.pinned,
      _Filter.ignored => a.ignored,
      _Filter.external => _isExternal(a),
      _Filter.websiteOnly => a.isManaged && !a.downloadsAllowed,
    };
    if (!ok) return false;
    final q = _search.text.trim().toLowerCase();
    return q.isEmpty ||
        a.name.toLowerCase().contains(q) ||
        (a.author?.toLowerCase().contains(q) ?? false) ||
        a.folders.any((f) => f.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final inst = ref.watch(selectedInstallationProvider)!;
    if (_installationId != inst.id) {
      // Switching clients resets filter and selection, like the design.
      _installationId = inst.id;
      _selected.clear();
      _filter = _Filter.all;
    }
    final state = ref.watch(addonsProvider(inst.id));
    final ctrl = ref.read(addonsProvider(inst.id).notifier);
    final w = context.w;

    final addons = state.addons;
    _selected.removeWhere((id) => !addons.any((a) => a.id == id));
    final visible = addons.where(_matches).toList();
    final updates = state.updatable.length;
    final websiteOnly = addons
        .where((a) => a.isManaged && !a.downloadsAllowed)
        .length;
    final counts = {
      _Filter.all: addons.length,
      _Filter.updates: updates,
      _Filter.pinned: addons.where((a) => a.pinned).length,
      _Filter.ignored: addons.where((a) => a.ignored).length,
      _Filter.external: addons.where(_isExternal).length,
      _Filter.websiteOnly: websiteOnly,
    };
    final allChecked =
        visible.isNotEmpty && visible.every((a) => _selected.contains(a.id));
    final selectedAddons = addons
        .where((a) => _selected.contains(a.id))
        .toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Meine Addons', style: WText.title(context)),
                          const SizedBox(height: 4),
                          Text(
                            inst.addonsPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WText.mono(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    _ScanMenu(inst: inst),
                    const SizedBox(width: 8),
                    WButton(
                      label: state.checking ? 'Prüfe…' : 'Nach Updates suchen',
                      icon: Icons.sync_rounded,
                      onPressed: state.checking ? null : ctrl.checkUpdates,
                    ),
                    const SizedBox(width: 16),
                    WButton(
                      kind: WButtonKind.primary,
                      icon: Icons.download_rounded,
                      label: updates > 0
                          ? 'Alle aktualisieren ($updates)'
                          : 'Alles aktuell',
                      onPressed: updates > 0 ? ctrl.updateAll : null,
                    ),
                  ],
                ),
                if (websiteOnly > 0) ...[
                  const SizedBox(height: 16),
                  _WebsiteOnlyNotice(
                    count: websiteOnly,
                    onShow: () => setState(() => _filter = _Filter.websiteOnly),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 36,
                  child: _selected.isEmpty
                      ? Row(
                          children: [
                            SizedBox(
                              width: 280,
                              child: WInput(
                                controller: _search,
                                search: true,
                                hint: 'Installierte Addons filtern…',
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            for (final f in _Filter.values)
                              // Niche filters only appear when they apply.
                              if (counts[f]! > 0 ||
                                  _filter == f ||
                                  !_optionalFilters.contains(f)) ...[
                                _FilterPill(
                                  label: switch (f) {
                                    _Filter.all => 'Alle',
                                    _Filter.updates => 'Updates',
                                    _Filter.pinned => 'Gepinnt',
                                    _Filter.ignored => 'Ignoriert',
                                    _Filter.external => 'Extern',
                                    _Filter.websiteOnly => 'Nur Website',
                                  },
                                  count: counts[f]!,
                                  active: _filter == f,
                                  onTap: () => setState(() => _filter = f),
                                ),
                                const SizedBox(width: 4),
                              ],
                          ],
                        )
                      : _BatchBar(
                          count: _selected.length,
                          onUpdate: () {
                            ctrl.updateMany(selectedAddons);
                            setState(_selected.clear);
                          },
                          onPin: () {
                            final pin = !selectedAddons.every((a) => a.pinned);
                            ctrl.setPinned(_selected, pin);
                            setState(_selected.clear);
                          },
                          onIgnore: () {
                            final ignore = !selectedAddons.every(
                              (a) => a.ignored,
                            );
                            ctrl.setIgnored(_selected, ignore);
                            setState(_selected.clear);
                          },
                          onUninstall: () async {
                            final ok = await confirm(
                              context,
                              title:
                                  '${selectedAddons.length} Addons deinstallieren?',
                              message: selectedAddons
                                  .map((a) => '• ${a.name}')
                                  .join('\n'),
                              confirmLabel: 'Deinstallieren',
                              destructive: true,
                            );
                            if (!ok) return;
                            await ctrl.uninstallMany(selectedAddons);
                            setState(_selected.clear);
                          },
                          onClear: () => setState(_selected.clear),
                        ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          sliver: DecoratedSliver(
            decoration: BoxDecoration(
              color: w.surface,
              border: Border.all(color: w.border),
              borderRadius: BorderRadius.circular(8),
              boxShadow: w.shadow,
            ),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: w.alt,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      border: Border(bottom: BorderSide(color: w.border)),
                    ),
                    child: DefaultTextStyle(
                      style: WText.caps(w.muted, spacing: 0.8),
                      child: _Cols.row([
                        WCheckbox(
                          checked: allChecked,
                          onTap: () => setState(() {
                            if (allChecked) {
                              _selected.clear();
                            } else {
                              _selected.addAll(visible.map((a) => a.id));
                            }
                          }),
                        ),
                        const Text('ADDON'),
                        const Text('VERSION'),
                        const Text('QUELLE'),
                        const Text('SPIEL'),
                        const Text('STATUS'),
                        const SizedBox.shrink(),
                      ]),
                    ),
                  ),
                ),
                if (!state.loaded || (state.scanning && addons.isEmpty))
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  )
                else if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 32,
                      ),
                      child: Text(
                        addons.isEmpty
                            ? 'Noch keine Addons installiert – unter „Entdecken“ findest du welche.'
                            : 'Keine Addons für diesen Filter.',
                        textAlign: TextAlign.center,
                        style: WText.muted(context, size: 13),
                      ),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final a = visible[i];
                      return _AddonRow(
                        inst: inst,
                        addon: a,
                        last: i == visible.length - 1,
                        checked: _selected.contains(a.id),
                        queued: state.queued(a.id),
                        onToggle: () => setState(
                          () => _selected.contains(a.id)
                              ? _selected.remove(a.id)
                              : _selected.add(a.id),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Explains why some addons can only be updated from their website.
class _WebsiteOnlyNotice extends StatelessWidget {
  const _WebsiteOnlyNotice({required this.count, required this.onShow});

  final int count;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) => WNotice(
    '${count == 1 ? 'Ein Addon gibt' : '$count Addons gibt'} es nur über die '
    'Website: Die Autoren erlauben keine Downloads über '
    'Drittanbieter-Programme, und keine andere Quelle führt sie. Updates '
    'werden angezeigt, die Installation erfolgt über „Website“.',
    action: WButton(label: 'Anzeigen', small: true, onPressed: onShow),
  );
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final fg = active ? w.selFg : w.muted;
    return Hover(
      onTap: onTap,
      builder: (context, h) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? w.sel : (h ? w.alt : w.surface),
          border: Border.all(color: active ? WColors.blue : w.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: fg,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Opacity(
              opacity: 0.8,
              child: Text('$count', style: WText.mono(context, color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchBar extends StatelessWidget {
  const _BatchBar({
    required this.count,
    required this.onUpdate,
    required this.onPin,
    required this.onIgnore,
    required this.onUninstall,
    required this.onClear,
  });

  final int count;
  final VoidCallback onUpdate;
  final VoidCallback onPin;
  final VoidCallback onIgnore;
  final VoidCallback onUninstall;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    Widget action(String label, VoidCallback onTap, {Color? fg}) => Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Hover(
        onTap: onTap,
        builder: (context, h) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: h ? w.alt : w.surface,
            border: Border.all(color: w.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg ?? w.fg,
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: w.sel,
        border: Border.all(color: WColors.blueLight),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count ausgewählt',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: w.selFg,
              ),
            ),
          ),
          action('Aktualisieren', onUpdate),
          action('Pinnen', onPin),
          action('Ignorieren', onIgnore),
          action('Deinstallieren', onUninstall, fg: WColors.red),
          const SizedBox(width: 4),
          WIconButton(
            icon: Icons.close_rounded,
            iconSize: 14,
            size: 26,
            color: w.selFg,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

class _AddonRow extends ConsumerWidget {
  const _AddonRow({
    required this.inst,
    required this.addon,
    required this.last,
    required this.checked,
    required this.queued,
    required this.onToggle,
  });

  final WowInstallation inst;
  final InstalledAddon addon;
  final bool last;
  final bool checked;
  final QueueItem? queued;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final showNew = addon.newerAvailable && !addon.ignored;
    return Hover(
      onTap: () => ref.read(navProvider.notifier).openAddon(addon.id),
      builder: (context, h) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: checked ? w.sel : (h ? w.hover : Colors.transparent),
          borderRadius: last
              ? const BorderRadius.vertical(bottom: Radius.circular(8))
              : null,
          border: last ? null : Border(bottom: BorderSide(color: w.border)),
        ),
        child: _Cols.row([
          WCheckbox(checked: checked, onTap: onToggle),
          Row(
            children: [
              InitialsTile(name: addon.name, url: addon.thumbnailUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      addon.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: w.fg,
                      ),
                    ),
                    Text(
                      addon.author ?? addon.folders.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WText.muted(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                addon.installedVersion ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WText.mono(context, size: 12, color: w.fg2),
              ),
              if (showNew)
                Text(
                  '→ ${addon.latestRelease!.version}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WText.mono(context, size: 12, color: WColors.orange),
                ),
            ],
          ),
          SourceBadge(addon.source, external: addon.external),
          Text(
            gameVersionOf(addon, inst),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: WText.mono(context, size: 12),
          ),
          StatusPill.of(context, addon),
          _action(context, ref),
        ]),
      ),
    );
  }

  Widget _action(BuildContext context, WidgetRef ref) {
    final q = queued;
    if (q != null) {
      return Row(
        children: [
          Expanded(child: WProgress(value: q.progress)),
          SizedBox(
            width: 36,
            child: Text(
              '${(q.progress * 100).round()}%',
              textAlign: TextAlign.right,
              style: WText.mono(context),
            ),
          ),
        ],
      );
    }
    if (addon.updateNeedsWebsite) {
      return WButton(
        label: 'Website',
        icon: Icons.open_in_new_rounded,
        kind: WButtonKind.outlineBlue,
        small: true,
        onPressed: () => openUrl(addon.websiteUrl),
      );
    }
    if (addon.hasUpdate) {
      return WButton(
        label: 'Aktualisieren',
        kind: WButtonKind.outlineBlue,
        small: true,
        onPressed: () =>
            ref.read(addonsProvider(inst.id).notifier).update(addon),
      );
    }
    return Text('—', style: WText.muted(context));
  }
}

/// Game version an addon targets on this client, from its TOC interface.
String gameVersionOf(InstalledAddon addon, WowInstallation inst) {
  final match =
      addon.interfaces
          .where((i) => GameFlavor.fromInterface(i) == inst.flavor)
          .firstOrNull ??
      addon.interfaces.firstOrNull;
  if (match != null) return formatInterface(match);
  final v = inst.gameVersion;
  if (v == null) return '—';
  return v.split('.').take(3).join('.');
}

class _ScanMenu extends ConsumerWidget {
  const _ScanMenu({required this.inst});

  final WowInstallation inst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(addonsProvider(inst.id).notifier);
    final scanning = ref.watch(
      addonsProvider(inst.id).select((s) => s.scanning),
    );
    return MenuAnchor(
      builder: (context, menu, _) => Tooltip(
        message: 'Scannen',
        child: Hover(
          onTap: scanning
              ? null
              : () => menu.isOpen ? menu.close() : menu.open(),
          builder: (context, h) => Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: h ? context.w.alt : context.w.surface,
              border: Border.all(color: context.w.strong),
              borderRadius: BorderRadius.circular(6),
            ),
            child: scanning
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.more_horiz_rounded, size: 18, color: context.w.fg),
          ),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.folder_outlined, size: 18),
          onPressed: ctrl.rescan,
          child: const Text('Addon-Ordner neu scannen'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.auto_fix_high_outlined, size: 18),
          onPressed: () => ctrl.rescan(rematch: true),
          child: const Text('Alle Addons neu zuordnen'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.open_in_new_rounded, size: 18),
          onPressed: () => openFolder(inst.addonsPath),
          child: const Text('AddOns-Ordner öffnen'),
        ),
      ],
    );
  }
}
