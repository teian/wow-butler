/// Version from `pubspec.yaml`, which `flutter run` and `flutter build` pass
/// to the app as `FLUTTER_BUILD_NAME`. Plain Dart code (no Flutter import)
/// so the scripts in `tool/` can use it as well; there, and under
/// `dart run`, the value is `null`.
///
/// The version is a plain SemVer version without build number.
const String? appVersion = bool.hasEnvironment('FLUTTER_BUILD_NAME')
    ? String.fromEnvironment('FLUTTER_BUILD_NAME')
    : null;

/// `1.2.0`, or `dev` when the app was not started by the Flutter tool.
String get appVersionLabel => appVersion ?? 'dev';
