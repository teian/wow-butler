import 'package:path/path.dart' as p;

import 'game_flavor.dart';

/// One game client (e.g. `World of Warcraft/_retail_`) the user manages.
class WowInstallation {
  const WowInstallation({
    required this.id,
    required this.label,
    required this.clientPath,
    required this.clientType,
    required this.flavor,
    this.gameVersion,
  });

  /// Stable identifier derived from the client path.
  final String id;
  final String label;

  /// Absolute path of the client folder (the one containing `Interface`).
  final String clientPath;
  final WowClientType clientType;
  final GameFlavor flavor;

  /// Full client version from `.build.info`, e.g. `11.2.0.62213`.
  final String? gameVersion;

  String get addonsPath => p.join(clientPath, 'Interface', 'AddOns');
  String get interfacePath => p.join(clientPath, 'Interface');
  String get wtfPath => p.join(clientPath, 'WTF');

  /// Filesystem-safe name used for backup folders.
  String get slug => '${clientType.name}-${id.substring(0, 8)}';

  WowInstallation copyWith({
    String? label,
    GameFlavor? flavor,
    String? gameVersion,
  }) => WowInstallation(
    id: id,
    label: label ?? this.label,
    clientPath: clientPath,
    clientType: clientType,
    flavor: flavor ?? this.flavor,
    gameVersion: gameVersion ?? this.gameVersion,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'clientPath': clientPath,
    'clientType': clientType.name,
    'flavor': flavor.name,
    'gameVersion': gameVersion,
  };

  factory WowInstallation.fromJson(Map<String, dynamic> json) {
    final clientType =
        WowClientType.tryParse(json['clientType'] as String?) ??
        WowClientType.retail;
    return WowInstallation(
      id: json['id'] as String,
      label: json['label'] as String,
      clientPath: json['clientPath'] as String,
      clientType: clientType,
      flavor:
          GameFlavor.tryParse(json['flavor'] as String?) ??
          clientType.defaultFlavor,
      gameVersion: json['gameVersion'] as String?,
    );
  }
}

/// Release maturity. Ordered from most to least stable, so a channel accepts
/// every release whose index is `<=` its own.
enum ReleaseChannel {
  stable('Stable'),
  beta('Beta'),
  alpha('Alpha');

  const ReleaseChannel(this.label);

  final String label;

  bool accepts(ReleaseChannel release) => release.index <= index;

  static ReleaseChannel? tryParse(String? name) =>
      ReleaseChannel.values.where((c) => c.name == name).firstOrNull;
}
