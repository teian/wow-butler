import 'package:flutter_test/flutter_test.dart';
import 'package:wow_butler/sources/description.dart';

void main() {
  test('markdown: paragraphs, features and screenshots', () {
    final d = detailsFromDescription(
      markdown: '''
# Baganator
![Build](https://img.shields.io/badge/build-passing.svg)

Fasst alle Taschen in einer Ansicht zusammen oder trennt sie nach
Kategorien. Siehe [Wiki](https://example.org).

## Features
- Einzel- und **Kategorieansicht**
- Suche über alle Charaktere

![Screenshot](https://cdn.example.org/shot1.png)
''',
    );
    expect(d.paragraphs, [
      'Fasst alle Taschen in einer Ansicht zusammen oder trennt sie nach '
          'Kategorien. Siehe Wiki.',
    ]);
    expect(d.features, [
      'Einzel- und Kategorieansicht',
      'Suche über alle Charaktere',
    ]);
    expect(d.screenshots, ['https://cdn.example.org/shot1.png']);
  });

  test('html: headings dropped, list items become features', () {
    final d = detailsFromDescription(
      html:
          '<h2>Overview</h2><p>Shows Mythic+ scores in tooltips and the '
          'group finder.</p><ul><li>Scores</li><li>Raid progress</li></ul>'
          '<img src="https://cdn.example.org/a.jpg">',
      screenshots: ['https://media.example.org/b.png'],
    );
    expect(d.paragraphs, [
      'Shows Mythic+ scores in tooltips and the group finder.',
    ]);
    expect(d.features, ['Scores', 'Raid progress']);
    expect(d.screenshots, [
      'https://media.example.org/b.png',
      'https://cdn.example.org/a.jpg',
    ]);
  });
}
