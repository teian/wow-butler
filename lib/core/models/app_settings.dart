import 'addon.dart';
import 'wow_installation.dart';

enum AppThemeMode { system, light, dark }

/// Periodic zip snapshots into a user chosen directory.
class ZipBackupSettings {
  const ZipBackupSettings({
    this.enabled = false,
    this.directory,
    this.includeAddons = true,
    this.includeWtf = true,
    this.intervalHours = 24,
    this.retention = 10,
    this.lastRunAt,
  });

  final bool enabled;
  final String? directory;
  final bool includeAddons;
  final bool includeWtf;

  /// 0 disables scheduled runs; manual runs still work.
  final int intervalHours;

  /// Number of archives kept per installation. 0 keeps everything.
  final int retention;
  final DateTime? lastRunAt;

  bool get isConfigured => directory != null && directory!.isNotEmpty;

  ZipBackupSettings copyWith({
    bool? enabled,
    String? directory,
    bool? includeAddons,
    bool? includeWtf,
    int? intervalHours,
    int? retention,
    DateTime? lastRunAt,
  }) => ZipBackupSettings(
    enabled: enabled ?? this.enabled,
    directory: directory ?? this.directory,
    includeAddons: includeAddons ?? this.includeAddons,
    includeWtf: includeWtf ?? this.includeWtf,
    intervalHours: intervalHours ?? this.intervalHours,
    retention: retention ?? this.retention,
    lastRunAt: lastRunAt ?? this.lastRunAt,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'directory': directory,
    'includeAddons': includeAddons,
    'includeWtf': includeWtf,
    'intervalHours': intervalHours,
    'retention': retention,
    'lastRunAt': lastRunAt?.toIso8601String(),
  };

  factory ZipBackupSettings.fromJson(Map<String, dynamic> json) =>
      ZipBackupSettings(
        enabled: json['enabled'] as bool? ?? false,
        directory: json['directory'] as String?,
        includeAddons: json['includeAddons'] as bool? ?? true,
        includeWtf: json['includeWtf'] as bool? ?? true,
        intervalHours: json['intervalHours'] as int? ?? 24,
        retention: json['retention'] as int? ?? 10,
        lastRunAt: DateTime.tryParse(json['lastRunAt'] as String? ?? ''),
      );
}

/// Versioned backups of addons and settings in a git repository.
class GitBackupSettings {
  const GitBackupSettings({
    this.enabled = false,
    this.repoPath,
    this.remoteUrl,
    this.branch = 'main',
    this.includeAddonFiles = true,
    this.includeWtf = true,
    this.autoPush = false,
    this.intervalHours = 24,
    this.lastRunAt,
  });

  final bool enabled;
  final String? repoPath;
  final String? remoteUrl;
  final String branch;

  /// When false only the addon manifest is committed, which is enough to
  /// reinstall everything from the sources and keeps the repository small.
  final bool includeAddonFiles;
  final bool includeWtf;
  final bool autoPush;
  final int intervalHours;
  final DateTime? lastRunAt;

  bool get isConfigured => repoPath != null && repoPath!.isNotEmpty;

  GitBackupSettings copyWith({
    bool? enabled,
    String? repoPath,
    String? remoteUrl,
    String? branch,
    bool? includeAddonFiles,
    bool? includeWtf,
    bool? autoPush,
    int? intervalHours,
    DateTime? lastRunAt,
  }) => GitBackupSettings(
    enabled: enabled ?? this.enabled,
    repoPath: repoPath ?? this.repoPath,
    remoteUrl: remoteUrl ?? this.remoteUrl,
    branch: branch ?? this.branch,
    includeAddonFiles: includeAddonFiles ?? this.includeAddonFiles,
    includeWtf: includeWtf ?? this.includeWtf,
    autoPush: autoPush ?? this.autoPush,
    intervalHours: intervalHours ?? this.intervalHours,
    lastRunAt: lastRunAt ?? this.lastRunAt,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'repoPath': repoPath,
    'remoteUrl': remoteUrl,
    'branch': branch,
    'includeAddonFiles': includeAddonFiles,
    'includeWtf': includeWtf,
    'autoPush': autoPush,
    'intervalHours': intervalHours,
    'lastRunAt': lastRunAt?.toIso8601String(),
  };

  factory GitBackupSettings.fromJson(Map<String, dynamic> json) =>
      GitBackupSettings(
        enabled: json['enabled'] as bool? ?? false,
        repoPath: json['repoPath'] as String?,
        remoteUrl: json['remoteUrl'] as String?,
        branch: json['branch'] as String? ?? 'main',
        includeAddonFiles: json['includeAddonFiles'] as bool? ?? true,
        includeWtf: json['includeWtf'] as bool? ?? true,
        autoPush: json['autoPush'] as bool? ?? false,
        intervalHours: json['intervalHours'] as int? ?? 24,
        lastRunAt: DateTime.tryParse(json['lastRunAt'] as String? ?? ''),
      );
}

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.installations = const [],
    this.selectedInstallationId,
    this.sourcePriority = defaultSourcePriority,
    this.disabledSources = const {},
    this.curseforgeApiKey,
    this.wagoApiKey,
    this.githubToken,
    this.updateCheckMinutes = 360,
    this.autoUpdate = true,
    this.checkOnStart = true,
    this.defaultChannel = ReleaseChannel.stable,
    this.backupBeforeUpdate = true,
    this.zipBackup = const ZipBackupSettings(),
    this.gitBackup = const GitBackupSettings(),
  });

  static const defaultSourcePriority = [
    AddonSourceId.tukui,
    AddonSourceId.wago,
    AddonSourceId.curseforge,
    AddonSourceId.wowup,
    AddonSourceId.wowinterface,
    AddonSourceId.github,
  ];

  final AppThemeMode themeMode;
  final List<WowInstallation> installations;
  final String? selectedInstallationId;

  /// Order in which sources are asked when matching unknown folders.
  final List<AddonSourceId> sourcePriority;
  final Set<AddonSourceId> disabledSources;
  final String? curseforgeApiKey;
  final String? wagoApiKey;
  final String? githubToken;

  /// 0 disables background update checks.
  final int updateCheckMinutes;

  /// Install updates automatically (at start and on every check). Pinned,
  /// ignored and opted-out addons are left alone.
  final bool autoUpdate;
  final bool checkOnStart;

  /// Channel for newly installed or matched addons.
  final ReleaseChannel defaultChannel;

  /// Zip the WTF folder before an update run, so addon settings can be
  /// restored if a new version breaks them.
  final bool backupBeforeUpdate;
  final ZipBackupSettings zipBackup;
  final GitBackupSettings gitBackup;

  WowInstallation? get selectedInstallation =>
      installations.where((i) => i.id == selectedInstallationId).firstOrNull ??
      installations.firstOrNull;

  bool isSourceEnabled(AddonSourceId id) => !disabledSources.contains(id);

  AppSettings copyWith({
    AppThemeMode? themeMode,
    List<WowInstallation>? installations,
    String? selectedInstallationId,
    List<AddonSourceId>? sourcePriority,
    Set<AddonSourceId>? disabledSources,
    String? curseforgeApiKey,
    String? wagoApiKey,
    String? githubToken,
    int? updateCheckMinutes,
    bool? autoUpdate,
    bool? checkOnStart,
    ReleaseChannel? defaultChannel,
    bool? backupBeforeUpdate,
    ZipBackupSettings? zipBackup,
    GitBackupSettings? gitBackup,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    installations: installations ?? this.installations,
    selectedInstallationId:
        selectedInstallationId ?? this.selectedInstallationId,
    sourcePriority: sourcePriority ?? this.sourcePriority,
    disabledSources: disabledSources ?? this.disabledSources,
    curseforgeApiKey: curseforgeApiKey ?? this.curseforgeApiKey,
    wagoApiKey: wagoApiKey ?? this.wagoApiKey,
    githubToken: githubToken ?? this.githubToken,
    updateCheckMinutes: updateCheckMinutes ?? this.updateCheckMinutes,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    checkOnStart: checkOnStart ?? this.checkOnStart,
    defaultChannel: defaultChannel ?? this.defaultChannel,
    backupBeforeUpdate: backupBeforeUpdate ?? this.backupBeforeUpdate,
    zipBackup: zipBackup ?? this.zipBackup,
    gitBackup: gitBackup ?? this.gitBackup,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'installations': installations.map((i) => i.toJson()).toList(),
    'selectedInstallationId': selectedInstallationId,
    'sourcePriority': sourcePriority.map((s) => s.name).toList(),
    'disabledSources': disabledSources.map((s) => s.name).toList(),
    'curseforgeApiKey': curseforgeApiKey,
    'wagoApiKey': wagoApiKey,
    'githubToken': githubToken,
    'updateCheckMinutes': updateCheckMinutes,
    'autoUpdate': autoUpdate,
    'checkOnStart': checkOnStart,
    'defaultChannel': defaultChannel.name,
    'backupBeforeUpdate': backupBeforeUpdate,
    'zipBackup': zipBackup.toJson(),
    'gitBackup': gitBackup.toJson(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final priority = [
      for (final name in (json['sourcePriority'] as List?) ?? const [])
        ?AddonSourceId.tryParse(name as String),
    ];
    // Sources added in newer versions go to the end of the stored order.
    for (final id in defaultSourcePriority) {
      if (!priority.contains(id)) priority.add(id);
    }
    return AppSettings(
      themeMode:
          AppThemeMode.values
              .where((m) => m.name == json['themeMode'])
              .firstOrNull ??
          AppThemeMode.system,
      installations: [
        for (final i in (json['installations'] as List?) ?? const [])
          WowInstallation.fromJson(i as Map<String, dynamic>),
      ],
      selectedInstallationId: json['selectedInstallationId'] as String?,
      sourcePriority: priority,
      disabledSources: {
        for (final name in (json['disabledSources'] as List?) ?? const [])
          ?AddonSourceId.tryParse(name as String),
      },
      curseforgeApiKey: json['curseforgeApiKey'] as String?,
      wagoApiKey: json['wagoApiKey'] as String?,
      githubToken: json['githubToken'] as String?,
      updateCheckMinutes: json['updateCheckMinutes'] as int? ?? 360,
      autoUpdate: json['autoUpdate'] as bool? ?? true,
      checkOnStart: json['checkOnStart'] as bool? ?? true,
      defaultChannel:
          ReleaseChannel.tryParse(json['defaultChannel'] as String?) ??
          ReleaseChannel.stable,
      backupBeforeUpdate: json['backupBeforeUpdate'] as bool? ?? true,
      zipBackup: ZipBackupSettings.fromJson(
        (json['zipBackup'] as Map<String, dynamic>?) ?? const {},
      ),
      gitBackup: GitBackupSettings.fromJson(
        (json['gitBackup'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}
