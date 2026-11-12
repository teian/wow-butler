import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/addon.dart';
import '../../core/models/wow_installation.dart';
import '../../services/download_watcher.dart';
import '../../state/activity_log.dart';
import '../../state/addons_controller.dart';
import '../../state/providers.dart';
import '../tokens.dart';
import 'primitives.dart';

/// Installs an addon whose author disallows downloads through third-party
/// tools: the user downloads [release] on the website, and the file is
/// picked up from the downloads folder (or chosen by hand) and installed.
Future<void> showWebsiteInstallDialog(
  BuildContext context, {
  required WowInstallation inst,
  required RemoteAddon remote,
  required AddonRelease release,
  ReleaseChannel? channel,
}) => showDialog(
  context: context,
  barrierDismissible: false,
  builder: (_) => _WebsiteInstallDialog(
    inst: inst,
    remote: remote,
    release: release,
    channel: channel,
  ),
);

/// [showWebsiteInstallDialog] for the update of an installed addon.
Future<void> showWebsiteUpdateDialog(
  BuildContext context,
  WidgetRef ref, {
  required WowInstallation inst,
  required InstalledAddon addon,
}) async {
  try {
    final plan = await ref
        .read(addonServiceProvider)
        .planUpdate(inst, addon, force: true);
    if (!context.mounted) return;
    await showWebsiteInstallDialog(
      context,
      inst: inst,
      remote: plan.remote,
      release: plan.release,
      channel: addon.channel,
    );
  } catch (e) {
    ref.read(activityProvider.notifier).error('${addon.name}: $e');
  }
}

enum _Phase { waiting, installing }

class _WebsiteInstallDialog extends ConsumerStatefulWidget {
  const _WebsiteInstallDialog({
    required this.inst,
    required this.remote,
    required this.release,
    this.channel,
  });

  final WowInstallation inst;
  final RemoteAddon remote;
  final AddonRelease release;
  final ReleaseChannel? channel;

  @override
  ConsumerState<_WebsiteInstallDialog> createState() =>
      _WebsiteInstallDialogState();
}

class _WebsiteInstallDialogState extends ConsumerState<_WebsiteInstallDialog> {
  DownloadWatcher? _watcher;
  String? _watchedDir;
  var _phase = _Phase.waiting;

  String get _fileName => widget.release.fileName ?? '';

  String? get _pageUrl => ref
      .read(sourcesProvider)[widget.remote.source]
      .websiteDownloadUrl(widget.remote, widget.release);

  @override
  void initState() {
    super.initState();
    // Opening the dialog is the user's request to download: open the
    // download page right away, the browser then starts the download.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) openUrl(_pageUrl);
    });
  }

  @override
  void dispose() {
    _watcher?.cancel();
    super.dispose();
  }

  /// (Re)starts watching [dir] for the download.
  void _watch(String? dir) {
    if (dir == null || dir == _watchedDir) return;
    _watcher?.cancel();
    _watchedDir = dir;
    final watcher = DownloadWatcher(
      directory: Directory(dir),
      fileName: _fileName,
      addonName: widget.remote.name,
    );
    _watcher = watcher;
    watcher.wait().then((file) {
      if (mounted && _watcher == watcher) _install(file);
    });
  }

  Future<void> _install(File file) async {
    if (_phase == _Phase.installing) return;
    _watcher?.cancel();
    setState(() => _phase = _Phase.installing);
    final navigator = Navigator.of(context);
    final ok = await ref
        .read(addonsProvider(widget.inst.id).notifier)
        .install(
          widget.remote,
          widget.release,
          channel: widget.channel,
          archive: file,
        );
    if (!mounted) return;
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _phase = _Phase.waiting);
      final dir = _watchedDir;
      _watchedDir = null;
      _watch(dir);
    }
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '${widget.remote.name}: heruntergeladene Datei wählen',
      initialDirectory: _watchedDir,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = picked?.path;
    if (path == null || !mounted) return;
    if (_fileName.isNotEmpty &&
        !DownloadWatcher.matches(p.basename(path), _fileName)) {
      final ok = await confirm(
        context,
        title: 'Andere Datei installieren?',
        message:
            'Erwartet wird „$_fileName“, gewählt wurde '
            '„${p.basename(path)}“. Die Datei wird trotzdem als '
            '${widget.remote.name} ${widget.release.version} installiert.',
        confirmLabel: 'Installieren',
      );
      if (!ok || !mounted) return;
    }
    await _install(File(path));
  }

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final dir = ref.watch(downloadsDirectoryProvider).value;
    _watch(dir);
    final pageUrl = _pageUrl;
    final installing = _phase == _Phase.installing;

    Widget step(int n, String title, Widget body) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: w.alt,
              border: Border.all(color: w.strong),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: w.fg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: w.fg,
                  ),
                ),
                const SizedBox(height: 6),
                body,
              ],
            ),
          ),
        ],
      ),
    );

    return Dialog(
      backgroundColor: w.surface,
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.remote.name} ${widget.release.version} '
              'über ${widget.remote.source.label} laden',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: w.fg,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Der Autor erlaubt keine direkten Downloads über '
              'Drittanbieter-Programme. Die Downloadseite wurde im Browser '
              'geöffnet; der Download startet dort nach wenigen Sekunden. '
              'WoW Butler installiert die Datei dann und hält das Addon wie '
              'gewohnt aktuell.',
              style: TextStyle(fontSize: 12, color: w.muted),
            ),
            step(
              1,
              'Im Browser herunterladen',
              Align(
                alignment: Alignment.centerLeft,
                child: WButton(
                  label: 'Downloadseite erneut öffnen',
                  icon: Icons.open_in_new_rounded,
                  small: true,
                  onPressed: pageUrl == null || installing
                      ? null
                      : () => openUrl(pageUrl),
                ),
              ),
            ),
            step(
              2,
              installing ? 'Wird installiert …' : 'Auf den Download warten',
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      installing
                          ? 'Die Datei wird entpackt und installiert.'
                          : dir == null
                          ? 'Kein Download-Ordner bekannt. Lege ihn in den '
                                'Einstellungen fest oder wähle die Datei aus.'
                          : 'Sobald ${_fileName.isEmpty ? 'die ZIP-Datei' : '„$_fileName“'} '
                                'in $dir liegt, startet die Installation '
                                'automatisch.',
                      style: TextStyle(fontSize: 12, color: w.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                WButton(
                  label: 'Datei auswählen …',
                  icon: Icons.folder_open_rounded,
                  small: true,
                  tooltip: 'Falls der Browser woanders speichert',
                  onPressed: installing ? null : _pickFile,
                ),
                const Spacer(),
                WButton(
                  label: 'Abbrechen',
                  kind: WButtonKind.ghost,
                  small: true,
                  onPressed: installing
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
