import 'package:flutter_test/flutter_test.dart';
import 'package:wow_butler/sources/github_source.dart';

void main() {
  group('GitHubSource.parseRepo', () {
    test('accepts owner/repo and repository URLs', () {
      expect(GitHubSource.parseRepo('Owner/Repo'), 'Owner/Repo');
      expect(
        GitHubSource.parseRepo('https://github.com/Owner/Repo'),
        'Owner/Repo',
      );
      expect(
        GitHubSource.parseRepo('https://github.com/Owner/Repo.git'),
        'Owner/Repo',
      );
      expect(
        GitHubSource.parseRepo('github.com/Owner/Repo/releases/tag/v1'),
        'Owner/Repo',
      );
    });

    test('resolves known project sites to their repository', () {
      const repo = 'EllesmereGaming/EllesmereUI';
      expect(GitHubSource.parseRepo('https://ellesmereui.com/'), repo);
      expect(GitHubSource.parseRepo('https://www.ellesmereui.com/download'), repo);
      expect(GitHubSource.parseRepo('ellesmereui.com'), repo);
    });

    test('rejects plain words', () {
      expect(GitHubSource.parseRepo('ellesmere'), isNull);
      expect(GitHubSource.parseRepo('details damage meter'), isNull);
    });
  });
}
