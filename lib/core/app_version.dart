/// Version from `pubspec.yaml`, which `flutter run` and `flutter build` pass
/// to the app as `FLUTTER_BUILD_NAME` and `FLUTTER_BUILD_NUMBER`. Plain Dart
/// code (no Flutter import) so the scripts in `tool/` can use it as well;
/// there, and under `dart run`, the values are `null`.
const String? appVersion = bool.hasEnvironment('FLUTTER_BUILD_NAME')
    ? String.fromEnvironment('FLUTTER_BUILD_NAME')
    : null;

const String? appBuildNumber = bool.hasEnvironment('FLUTTER_BUILD_NUMBER')
    ? String.fromEnvironment('FLUTTER_BUILD_NUMBER')
    : null;

/// `1.1.0 (2)`, or `dev` when the app was not started by the Flutter tool.
String get appVersionLabel => switch ((appVersion, appBuildNumber)) {
  (final String v, final String b) when b.isNotEmpty => '$v ($b)',
  (final String v, _) => v,
  _ => 'dev',
};
