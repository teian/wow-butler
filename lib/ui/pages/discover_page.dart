import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/addon.dart';
import '../../core/models/addon_category.dart';
import '../../core/models/wow_installation.dart';
import '../../services/addon_service.dart' show websiteOnlyMessage;
import '../../state/addons_controller.dart';
import '../../state/discover_controller.dart';
import '../../state/nav_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../format.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  late final _search = TextEditingController(
    text: ref.read(discoverProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inst = ref.watch(selectedInstallationProvider)!;
    final state = ref.watch(discoverProvider);
    final ctrl = ref.read(discoverProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final registry = ref.watch(sourcesProvider);
    final w = context.w;

    final enabled = [
      for (final s in registry.all)
        if (settings.isSourceEnabled(s.id)) s,
    ];
    final problems = <String>[
      for (final s in enabled)
        if (s.unavailableReason != null)
          '${s.id.label}: ${s.unavailableReason}'
        else if (state.errors[s.id] != null)
          '${s.id.label}: ${state.errors[s.id]}',
    ];
    final results = state.visible;
    final pairs = (results.length / 2).ceil();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Entdecken', style: WText.title(context)),
                const SizedBox(height: 4),
                Text(
                  'Durchsucht aktive Quellen für ${inst.label} '
                  '${inst.gameVersion?.split('.').take(3).join('.') ?? inst.flavor.label}'
                  ' – GitHub-Repositories als owner/repo oder URL einfügen, '
                  'Kategorien auch als Suchbegriff (z. B. „minimap", „quests")',
                  style: WText.muted(context, size: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: SizedBox(
                        width: 460,
                        child: WInput(
                          controller: _search,
                          search: true,
                          fontSize: 14,
                          hint: 'Addons auf allen Quellen suchen…',
                          onChanged: ctrl.setQuery,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    WSegmented<AddonSourceId?>(
                      options: [
                        (null, 'Alle'),
                        for (final s in enabled) (s.id, s.id.label),
                      ],
                      value: state.sourceFilter,
                      onChanged: ctrl.setFilter,
                    ),
                    const Spacer(),
                    if (state.loading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      WIconButton(
                        icon: Icons.sync_rounded,
                        tooltip: 'Neu laden',
                        onPressed: ctrl.refresh,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _CategoryChip(
                      label: 'Alle',
                      selected: state.category == null,
                      onTap: () => ctrl.setCategory(null),
                    ),
                    for (final c in AddonCategory.values)
                      _CategoryChip(
                        label: c.label,
                        selected: state.category == c,
                        onTap: () =>
                            ctrl.setCategory(state.category == c ? null : c),
                      ),
                  ],
                ),
                if (problems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final p in problems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: WColors.amber,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              p,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WText.muted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (results.isEmpty && !state.loading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                'Keine Treffer. Suchbegriff, Kategorie oder Quelle anpassen.',
                textAlign: TextAlign.center,
                style: WText.muted(context, size: 13),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            sliver: SliverList.builder(
              itemCount: pairs,
              itemBuilder: (context, i) {
                final left = results[i * 2];
                final right = i * 2 + 1 < results.length
                    ? results[i * 2 + 1]
                    : null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _ResultCard(addon: left)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: right == null
                              ? const SizedBox.shrink()
                              : _ResultCard(addon: right),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (state.loading && results.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: WProgress(value: null, color: w.strong),
            ),
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return Hover(
      onTap: onTap,
      builder: (context, h) => AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? w.sel : (h ? w.hover : w.chip),
          border: Border.all(
            color: selected ? WColors.blueLight : w.border,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? w.selFg : (h ? w.fg : w.muted),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.addon});

  final RemoteAddon addon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final inst = ref.watch(selectedInstallationProvider)!;
    final channel = ref.watch(settingsProvider.select((s) => s.defaultChannel));
    final release = releaseToInstall(addon, channel);
    final progress = ref.watch(
      addonsProvider(inst.id).select((s) => s.installing[addon.key]),
    );
    final installed = ref.watch(
      addonsProvider(inst.id)
          .select((s) => s.addons.any((a) => a.remoteKey == addon.key)),
    );

    final meta = [
      if (addon.downloadCount != null && addon.source != AddonSourceId.github)
        '${formatCount(addon.downloadCount)} DL',
      if (addon.source == AddonSourceId.github && addon.downloadCount != null)
        '★ ${formatCount(addon.downloadCount)}',
      if ((release?.releasedAt ?? addon.updatedAt) != null)
        formatRelative(release?.releasedAt ?? addon.updatedAt),
      if (release != null) release.version,
    ];

    final Widget action;
    if (progress != null) {
      action = SizedBox(
        width: 120,
        child: Row(
          children: [
            Expanded(child: WProgress(value: progress)),
            const SizedBox(width: 8),
            Text('${(progress * 100).round()}%', style: WText.mono(context)),
          ],
        ),
      );
    } else if (installed) {
      action = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: WColors.green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: WColors.green),
            SizedBox(width: 5),
            Text(
              'INSTALLIERT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: WColors.green,
              ),
            ),
          ],
        ),
      );
    } else if (!addon.downloadsAllowed) {
      action = const WButton(
        kind: WButtonKind.blue,
        small: true,
        icon: Icons.block_rounded,
        label: 'Nur über Website',
        tooltip: websiteOnlyMessage,
      );
    } else if (release == null) {
      action = Tooltip(
        message: 'Keine Version für ${inst.flavor.label} verfügbar',
        child: Text('Nicht verfügbar', style: WText.muted(context)),
      );
    } else {
      action = WButton(
        kind: WButtonKind.blue,
        small: true,
        icon: Icons.download_rounded,
        label: release.channel == ReleaseChannel.stable
            ? 'Installieren'
            : 'Installieren (${release.channel.label})',
        onPressed: () =>
            ref.read(addonsProvider(inst.id).notifier).install(addon, release),
      );
    }

    return Hover(
      onTap: () => ref.read(navProvider.notifier).openRemote(addon),
      builder: (context, h) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: w.surface,
          border: Border.all(color: w.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: h
              ? const [
                  BoxShadow(
                    color: Color(0x1A0F172A),
                    blurRadius: 6,
                    offset: Offset(0, 4),
                  ),
                ]
              : w.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InitialsTile(
                  name: addon.name,
                  url: addon.thumbnailUrl,
                  size: 40,
                ),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: w.fg,
                        ),
                      ),
                      if (addon.author != null)
                        Text(
                          addon.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WText.muted(context),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SourceBadge(addon.source),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Text(
                addon.summary ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.55, color: w.fg2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    meta.join('   '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WText.mono(context),
                  ),
                ),
                const SizedBox(width: 12),
                action,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
