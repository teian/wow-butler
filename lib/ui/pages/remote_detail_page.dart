import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/addon.dart';
import '../../core/models/game_flavor.dart';
import '../../core/models/wow_installation.dart';
import '../../state/addons_controller.dart';
import '../../state/detail_providers.dart';
import '../../state/discover_controller.dart';
import '../../state/nav_controller.dart';
import '../../state/settings_controller.dart';
import '../format.dart';
import '../theme.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';

/// Detail page of an addon found under "Entdecken".
class RemoteDetailPage extends ConsumerStatefulWidget {
  const RemoteDetailPage({super.key});

  @override
  ConsumerState<RemoteDetailPage> createState() => _RemoteDetailPageState();
}

class _RemoteDetailPageState extends ConsumerState<RemoteDetailPage> {
  int _shot = 0;
  String? _addonKey;

  @override
  Widget build(BuildContext context) {
    final addon = ref.watch(navProvider.select((n) => n.remote));
    if (addon == null) return const SizedBox.shrink();
    if (_addonKey != addon.key) {
      _addonKey = addon.key;
      _shot = 0;
    }
    final inst = ref.watch(selectedInstallationProvider)!;
    final details = ref.watch(remoteDetailsProvider(addon));
    final w = context.w;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Hover(
              onTap: () => ref.read(navProvider.notifier).go(AppView.browse),
              builder: (context, h) {
                final c = h ? w.fg : w.muted;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left_rounded, size: 18, color: c),
                    const SizedBox(width: 2),
                    Text(
                      'Entdecken',
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
          const SizedBox(height: 20),
          _Header(addon: addon, inst: inst, category: details.value?.category),
          const SizedBox(height: 20),
          details.when(
            loading: () => const _ShotPlaceholder(loading: true),
            error: (_, _) => const SizedBox.shrink(),
            data: (d) => d.screenshots.isEmpty
                ? _NoShots(source: addon.source)
                : _Gallery(
                    urls: d.screenshots,
                    index: _shot.clamp(0, d.screenshots.length - 1),
                    sourceLabel: addon.source.label,
                    onSelect: (i) => setState(() => _shot = i),
                  ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Description(addon: addon, details: details),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 320,
                child: Column(
                  children: [
                    _Meta(addon: addon, inst: inst),
                    const SizedBox(height: 16),
                    _Compat(addon: addon, flavors: details.value?.flavors),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.addon, required this.inst, this.category});

  final RemoteAddon addon;
  final WowInstallation inst;
  final String? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final channel = ref.watch(settingsProvider.select((s) => s.defaultChannel));
    final release = releaseToInstall(addon, channel);
    final progress = ref.watch(
      addonsProvider(inst.id).select((s) => s.installing[addon.key]),
    );
    final installed = ref.watch(
      addonsProvider(inst.id)
          .select((s) => s.addons.any((a) => a.remoteKey == addon.key)),
    );

    final Widget action;
    if (progress != null) {
      action = SizedBox(
        width: 180,
        child: Row(
          children: [
            Expanded(child: WProgress(value: progress, height: 6)),
            const SizedBox(width: 10),
            Text(
              '${(progress * 100).round()}%',
              style: WText.mono(context, size: 12),
            ),
          ],
        ),
      );
    } else if (installed) {
      action = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: WColors.green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 14, color: WColors.green),
            SizedBox(width: 6),
            Text(
              'INSTALLIERT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.55,
                color: WColors.green,
              ),
            ),
          ],
        ),
      );
    } else if (release == null) {
      action = Text(
        'Keine Version für ${inst.flavor.label}',
        style: WText.muted(context, size: 13),
      );
    } else {
      action = WButton(
        kind: WButtonKind.primary,
        icon: Icons.download_rounded,
        label: release.channel == ReleaseChannel.stable
            ? 'Installieren'
            : 'Installieren (${release.channel.label})',
        onPressed: () =>
            ref.read(addonsProvider(inst.id).notifier).install(addon, release),
      );
    }

    final c = sourceColors(context, addon.source);
    return Row(
      children: [
        InitialsTile(name: addon.name, url: addon.thumbnailUrl, size: 64),
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
                  WBadge(addon.source.label, fg: c.fg, bg: c.bg),
                  if (category != null) ...[
                    const SizedBox(width: 10),
                    WBadge(category!, fg: w.fg2, bg: w.chip),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (addon.websiteUrl != null) ...[
          const SizedBox(width: 16),
          WButton(
            label: 'Auf ${addon.source.label} öffnen',
            icon: Icons.open_in_new_rounded,
            onPressed: () => openUrl(addon.websiteUrl),
          ),
        ],
        const SizedBox(width: 8),
        action,
      ],
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.urls,
    required this.index,
    required this.sourceLabel,
    required this.onSelect,
  });

  final List<String> urls;
  final int index;
  final String sourceLabel;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final n = urls.length;

    Widget arrow(IconData icon, VoidCallback onTap) => Hover(
      onTap: onTap,
      builder: (context, h) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: h ? 0.8 : 0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: w.alt,
                border: Border.all(color: w.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Shot(
                    url: urls[index],
                    label: 'Screenshot ${index + 1} von $sourceLabel',
                  ),
                  if (n > 1) ...[
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: arrow(
                          Icons.chevron_left_rounded,
                          () => onSelect((index - 1 + n) % n),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: arrow(
                          Icons.chevron_right_rounded,
                          () => onSelect((index + 1) % n),
                        ),
                      ),
                    ),
                  ],
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${index + 1} / $n',
                        style: WText.mono(context, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (n > 1) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Hover(
                      onTap: () => onSelect(i),
                      builder: (context, h) => AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: i == index || h ? 1 : 0.6,
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: w.alt,
                              border: Border.all(
                                width: 2,
                                color: i == index ? WColors.orange : w.border,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: _Shot(
                              url: urls[i],
                              label: (i + 1).toString().padLeft(2, '0'),
                              thumbnail: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Network screenshot with the design's placeholder label as fallback.
class _Shot extends StatelessWidget {
  const _Shot({required this.url, required this.label, this.thumbnail = false});

  final String url;
  final String label;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(label, style: WText.mono(context, size: thumbnail ? 11 : 12)),
    );
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: thumbnail ? 320 : 1600,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (_, child, frame, sync) =>
          frame == null && !sync ? fallback : child,
    );
  }
}

class _ShotPlaceholder extends StatelessWidget {
  const _ShotPlaceholder({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 420),
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: context.w.alt,
          border: Border.all(color: context.w.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
    ),
  );
}

class _NoShots extends StatelessWidget {
  const _NoShots({required this.source});

  final AddonSourceId source;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return CustomPaint(
      painter: _DashedBorder(color: w.strong),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.image_outlined, size: 18, color: w.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Für dieses Addon stellt ${source.label} keine Screenshots bereit.',
                style: WText.muted(context, size: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

class _Description extends StatelessWidget {
  const _Description({required this.addon, required this.details});

  final RemoteAddon addon;
  final AsyncValue<AddonDetails> details;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final d = details.value;
    final paragraphs = (d == null || d.paragraphs.isEmpty)
        ? [?addon.summary]
        : d.paragraphs;
    return WCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('BESCHREIBUNG', style: WText.caps(w.muted)),
          const SizedBox(height: 16),
          if (details.isLoading && paragraphs.isEmpty)
            const WProgress(value: null)
          else if (paragraphs.isEmpty)
            Text(
              'Keine Beschreibung vorhanden.',
              style: WText.muted(context, size: 14),
            ),
          for (final (i, p) in paragraphs.indexed) ...[
            if (i > 0) const SizedBox(height: 16),
            Text(p, style: TextStyle(fontSize: 14, height: 1.65, color: w.fg2)),
          ],
          if (d != null && d.features.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final f in d.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle_outline_rounded,
                        size: 15,
                        color: WColors.green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        f,
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
        ],
      ),
    );
  }
}

class _Meta extends ConsumerWidget {
  const _Meta({required this.addon, required this.inst});

  final RemoteAddon addon;
  final WowInstallation inst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final channel = ref.watch(settingsProvider.select((s) => s.defaultChannel));
    final release = releaseToInstall(addon, channel);
    final version = release?.version;
    final interface =
        release?.interfaces
            .where((i) => GameFlavor.fromInterface(i) == inst.flavor)
            .firstOrNull ??
        release?.interfaces.firstOrNull;
    final rows = [
      (
        'Version',
        version == null
            ? '—'
            : version.length > 16
            ? '…${version.substring(version.length - 11)}'
            : version,
      ),
      ('Aktualisiert', formatRelative(release?.releasedAt ?? addon.updatedAt)),
      (
        addon.source == AddonSourceId.github ? 'Sterne' : 'Downloads',
        addon.downloadCount == null ? '—' : formatCount(addon.downloadCount),
      ),
      ('Größe', release?.size == null ? '—' : formatBytes(release!.size!)),
      (
        'Spielversion',
        interface != null
            ? formatInterface(interface)
            : inst.gameVersion?.split('.').take(3).join('.') ??
                  inst.flavor.label,
      ),
    ];
    return WCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Text('DETAILS', style: WText.caps(w.muted)),
          ),
          for (final (k, v) in rows)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: w.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      k,
                      style: TextStyle(fontSize: 13, color: w.muted),
                    ),
                  ),
                  Text(v, style: WText.mono(context, size: 12, color: w.fg)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Compat extends ConsumerWidget {
  const _Compat({required this.addon, required this.flavors});

  final RemoteAddon addon;
  final Set<GameFlavor>? flavors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final settings = ref.watch(settingsProvider);
    final current = settings.selectedInstallation;
    // Without source data, only the client the search ran for is certain.
    bool supports(WowInstallation i) =>
        flavors?.contains(i.flavor) ??
        (i.flavor == current?.flavor && addon.releases.isNotEmpty);
    final clients = [...settings.installations]
      ..sort((a, b) => (supports(a) ? 0 : 1).compareTo(supports(b) ? 0 : 1));

    return WCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('KOMPATIBEL MIT', style: WText.caps(w.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final i in clients)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: w.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: supports(i) ? WColors.green : w.strong,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        i.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: supports(i) ? w.fg : w.muted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
