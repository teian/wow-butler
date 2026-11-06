import 'package:flutter_test/flutter_test.dart';
import 'package:wow_butler/sources/api_client.dart';
import 'package:wow_butler/sources/curseforge_source.dart';

void main() {
  final api = ApiClient();

  group('CurseForgeSource.unavailableReason', () {
    test('asks for a key when none is set', () {
      expect(CurseForgeSource(api, null).unavailableReason, isNotNull);
      expect(CurseForgeSource(api, '').unavailableReason, isNotNull);
    });

    test('flags an authors token (UUID) as the wrong key type', () {
      final source = CurseForgeSource(
        api,
        '123e4567-e89b-12d3-a456-426614174000',
      );
      expect(source.unavailableReason, contains('console.curseforge.com'));
    });

    test('accepts a Core API key', () {
      final source = CurseForgeSource(
        api,
        r'$2a$10$abcdefghijklmnopqrstuvABCDEFGHIJKLMNOPQRSTUV0123456789',
      );
      expect(source.unavailableReason, isNull);
    });
  });
}
