import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/addon.dart';
import '../../core/models/game_flavor.dart';
import '../../core/models/wow_installation.dart';
import '../../services/addon_service.dart' show websiteOnlyMessage;
import '../../state/addons_controller.dart';
import '../../state/detail_providers.dart';
import '../../state/discover_controller.dart';
import '../../state/nav_controller.dart';
import '../../state/settings_controller.dart';
import '../format.dart';
import '../theme.dart';
import '../tokens.dart';
import '../widgets/addon_media.dart';
import '../widgets/primitives.dart';
import '../widgets/website_install_dialog.dart';

/// Detail page of an addon found under "Entdecken".
class RemoteDetailPage extends ConsumerStatefulWidget {
  const RemoteDetailPage({super.key});

  @override
  ConsumerState<RemoteDetailPage> createState() => _RemoteDetailPageState();
}

class _RemoteDetailPageState extends ConsumerState<RemoteDetailPage> {
  @override
  Widget build(BuildContext context) {
    final addon = ref.watch(navProvider.select((n) => n.remote));
    if (addon == null) return const SizedBox.shrink();
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
          if (!addon.downloadsAllowed) ...[
            const SizedBox(height: 16),
            WNotice(
              'Der Autor von ${addon.name} hat direkte Downloads über '
              'Drittanbieter-Programme wie WoW Butler abgeschaltet. Über '
              '„Über Website installieren“ lädst du die Datei im Browser '
              'herunter; WoW Butler installiert sie danach automatisch und '
              'zeigt weiter Updates an.',
              title: 'Download über die Website.',
            ),
          ],
          const SizedBox(height: 20),
          details.when(
            loading: () => const ScreenshotPlaceholder(loading: true),
            error: (_, _) => const SizedBox.shrink(),
            data: (d) => d.screenshots.isEmpty
                ? NoScreenshots(sourceLabel: addon.source.label)
                : ScreenshotGallery(
                    key: ValueKey(addon.key),
                    urls: d.screenshots,
                    sourceLabel: addon.source.label,
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
                    CompatCard(
                      flavors: details.value?.flavors,
                      currentSupported: addon.releases.isNotEmpty,
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
    } else if (!addon.downloadsAllowed && release != null) {
      action = WButton(
        kind: WButtonKind.primary,
        icon: Icons.open_in_new_rounded,
        label: 'Über Website installieren',
        tooltip: websiteOnlyMessage,
        onPressed: () => showWebsiteInstallDialog(
          context,
          inst: inst,
          remote: addon,
          release: release,
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

class _Description extends StatelessWidget {
  const _Description({required this.addon, required this.details});

  final RemoteAddon addon;
  final AsyncValue<AddonDetails> details;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return WCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('BESCHREIBUNG', style: WText.caps(w.muted)),
          const SizedBox(height: 16),
          DescriptionBody(
            details: details.value,
            loading: details.isLoading,
            fallbackSummary: addon.summary,
          ),
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
