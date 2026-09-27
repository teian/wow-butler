import '../core/models/addon.dart';
import '../core/models/game_flavor.dart';
import 'api_client.dart';

/// Builds [AddonDetails] from an HTML or Markdown description.
///
/// Headings are dropped, bullet points become features and the remaining
/// blocks become paragraphs. Screenshots embedded in the text are collected
/// in addition to [screenshots].
AddonDetails detailsFromDescription({
  String? html,
  String? markdown,
  List<String> screenshots = const [],
  String? category,
  Set<GameFlavor>? flavors,
}) {
  final blocks = <String>[];
  final images = <String>[...screenshots];

  if (markdown != null && markdown.trim().isNotEmpty) {
    images.addAll(_imageUrls(markdown));
    for (final block in markdown.split(RegExp(r'\n\s*\n'))) {
      blocks.addAll(_markdownBlock(block));
    }
  } else if (html != null && html.trim().isNotEmpty) {
    images.addAll(_imageUrls(html));
    final withoutHeadings = html.replaceAll(
      RegExp(r'<h[1-6][^>]*>.*?</h[1-6]>', caseSensitive: false, dotAll: true),
      '\n',
    );
    blocks.addAll(htmlToText(withoutHeadings).split('\n'));
  }

  final paragraphs = <String>[];
  final features = <String>[];
  for (final raw in blocks) {
    final line = raw.trim();
    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      final text = bullet.group(1)!.trim();
      if (text.length >= 3 && features.length < 8) {
        features.add(_clip(text, 180));
      }
    } else if (line.length >= 20 && paragraphs.length < 4) {
      paragraphs.add(_clip(line, 700));
    }
  }

  return AddonDetails(
    paragraphs: paragraphs,
    features: features,
    screenshots: images.toSet().take(10).toList(),
    category: category,
    flavors: flavors,
  );
}

final _bullet = RegExp(r'^(?:[-*+•]|\d+[.)])\s+(.*)$');

List<String> _markdownBlock(String block) {
  final lines = block
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('|'))
      .map(_markdownInline)
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const [];
  // A block of bullets stays line by line; prose lines form one paragraph.
  if (lines.every(_bullet.hasMatch)) return lines;
  final prose = lines.where((l) => !_bullet.hasMatch(l)).join(' ');
  return [prose, ...lines.where(_bullet.hasMatch)];
}

String _markdownInline(String line) {
  var s = line
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      )
      .replaceAll(RegExp(r'[*_`]{1,3}'), '');
  s = plainText(s, maxLength: 1 << 20);
  return s;
}

final _markdownImage = RegExp(r'!\[[^\]]*\]\((https?://[^)\s]+)');
final _htmlImage = RegExp(
  r'''<img[^>]+src=["'](https?://[^"']+)["']''',
  caseSensitive: false,
);

Iterable<String> _imageUrls(String text) =>
    [
      for (final m in _markdownImage.allMatches(text)) m.group(1)!,
      for (final m in _htmlImage.allMatches(text)) m.group(1)!,
    ].where((url) {
      final lower = url.toLowerCase();
      // Badges and icons are not screenshots.
      return !lower.contains('shields.io') &&
          !lower.contains('badge') &&
          !lower.endsWith('.svg') &&
          !lower.contains('patreon');
    });

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max).trimRight()}…';
