import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/addon.dart';
import '../../core/models/game_flavor.dart';
import '../../core/models/wow_installation.dart';
import '../../state/settings_controller.dart';
import '../tokens.dart';
import 'primitives.dart';

/// Screenshot gallery with thumbnail strip and a fullscreen lightbox,
/// shared by the discover and installed-addon detail pages.
class ScreenshotGallery extends StatefulWidget {
  const ScreenshotGallery({
    super.key,
    required this.urls,
    required this.sourceLabel,
  });

  final List<String> urls;
  final String sourceLabel;

  @override
  State<ScreenshotGallery> createState() => _ScreenshotGalleryState();
}

class _ScreenshotGalleryState extends State<ScreenshotGallery> {
  int _index = 0;

  Future<void> _openLightbox(BuildContext context) async {
    final result = await showDialog<int>(
      context: context,
      barrierColor: const Color(0xF20B1120),
      builder: (_) => _Lightbox(
        urls: widget.urls,
        index: _index,
        sourceLabel: widget.sourceLabel,
      ),
    );
    if (result != null && result != _index && mounted) {
      setState(() => _index = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final n = widget.urls.length;
    final index = _index.clamp(0, n - 1);

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
                  MouseRegion(
                    cursor: SystemMouseCursors.zoomIn,
                    child: GestureDetector(
                      onTap: () => _openLightbox(context),
                      child: _Shot(
                        url: widget.urls[index],
                        label:
                            'Screenshot ${index + 1} von ${widget.sourceLabel}',
                      ),
                    ),
                  ),
                  if (n > 1) ...[
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: arrow(
                          Icons.chevron_left_rounded,
                          () => setState(() => _index = (index - 1 + n) % n),
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
                          () => setState(() => _index = (index + 1) % n),
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
                      onTap: () => setState(() => _index = i),
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
                              url: widget.urls[i],
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
    // Decode for the physical pixels actually shown (box width × DPR),
    // otherwise screenshots blur on HiDPI displays.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.network(
      url,
      // The main view shows the whole screenshot and never blows small
      // images up; only the strip thumbnails may crop to fill their tile.
      fit: thumbnail ? BoxFit.cover : BoxFit.scaleDown,
      cacheWidth: ((thumbnail ? 160 : 800) * dpr).round(),
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (_, child, frame, sync) =>
          frame == null && !sync ? fallback : child,
    );
  }
}

/// Fullscreen screenshot viewer: zoom with the mouse wheel or pinch, pan
/// while zoomed, double click to toggle, arrow keys to browse.
class _Lightbox extends StatefulWidget {
  const _Lightbox({
    required this.urls,
    required this.index,
    required this.sourceLabel,
  });

  final List<String> urls;
  final int index;
  final String sourceLabel;

  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  late int _index = widget.index;
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final n = widget.urls.length;
    setState(() {
      _index = (_index + delta + n) % n;
      _transform.value = Matrix4.identity();
    });
  }

  void _toggleZoom() {
    setState(() {
      _transform.value = _transform.value.isIdentity()
          ? Matrix4.diagonal3Values(2.5, 2.5, 1)
          : Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.urls.length;

    Widget pill(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );

    Widget arrow(IconData icon, VoidCallback onTap) => Hover(
      onTap: onTap,
      builder: (context, h) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: h ? 0.9 : 0.7),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 22, color: Colors.white),
      ),
    );

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (n > 1 && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _go(-1);
          return KeyEventResult.handled;
        }
        if (n > 1 && event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _go(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Click on the empty area closes, like the barrier.
          GestureDetector(onTap: () => Navigator.of(context).pop(_index)),
          Center(
            child: InteractiveViewer(
              transformationController: _transform,
              maxScale: 6,
              child: GestureDetector(
                // Swallows plain taps so only the backdrop closes.
                onTap: () {},
                onDoubleTap: _toggleZoom,
                child: Image.network(
                  widget.urls[_index],
                  fit: BoxFit.scaleDown,
                  errorBuilder: (_, _, _) => pill(
                    Text(
                      'Screenshot konnte nicht geladen werden',
                      style: WText.mono(context, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (n > 1) ...[
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: arrow(Icons.chevron_left_rounded, () => _go(-1)),
              ),
            ),
            Positioned(
              right: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: arrow(Icons.chevron_right_rounded, () => _go(1)),
              ),
            ),
          ],
          Positioned(
            top: 16,
            right: 16,
            child: Hover(
              onTap: () => Navigator.of(context).pop(_index),
              builder: (context, h) => Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF0F172A,
                  ).withValues(alpha: h ? 0.9 : 0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: pill(
                Text(
                  '${_index + 1} / $n · ${widget.sourceLabel} · '
                  'Scrollen zum Zoomen, Doppelklick für 250 %',
                  style: WText.mono(context, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScreenshotPlaceholder extends StatelessWidget {
  const ScreenshotPlaceholder({super.key, this.loading = false});

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

class NoScreenshots extends StatelessWidget {
  const NoScreenshots({super.key, required this.sourceLabel});

  final String sourceLabel;

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
                'Für dieses Addon stellt $sourceLabel keine Screenshots bereit.',
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

/// Paragraphs and feature list of an addon description, without card
/// chrome, so both detail pages render the same content.
class DescriptionBody extends StatelessWidget {
  const DescriptionBody({
    super.key,
    required this.details,
    this.loading = false,
    this.fallbackSummary,
  });

  final AddonDetails? details;
  final bool loading;
  final String? fallbackSummary;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final d = details;
    final paragraphs = (d == null || d.paragraphs.isEmpty)
        ? [?fallbackSummary]
        : d.paragraphs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading && paragraphs.isEmpty)
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
                      style: TextStyle(fontSize: 13, height: 1.55, color: w.fg2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// "Kompatibel mit" card listing the user's clients, green when the addon
/// supports their flavor.
class CompatCard extends ConsumerWidget {
  const CompatCard({
    super.key,
    required this.flavors,
    this.currentSupported = true,
  });

  final Set<GameFlavor>? flavors;

  /// Assumed for the selected installation's flavor while the source has
  /// not reported any flavors.
  final bool currentSupported;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = context.w;
    final settings = ref.watch(settingsProvider);
    final current = settings.selectedInstallation;
    bool supports(WowInstallation i) =>
        flavors?.contains(i.flavor) ??
        (i.flavor == current?.flavor && currentSupported);
    // One chip per distinct client; several installs of the same client
    // and flavor would only repeat the same answer.
    final seen = <String>{};
    final clients = [
      for (final i in settings.installations)
        if (seen.add('${i.label}|${i.flavor.name}')) i,
    ]..sort((a, b) => (supports(a) ? 0 : 1).compareTo(supports(b) ? 0 : 1));

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
