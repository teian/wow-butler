import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'activity_log.dart';
import 'addons_controller.dart';
import 'settings_controller.dart';

/// Whether the desktop offers a system tray. Windows and macOS always do;
/// on Linux it needs a StatusNotifier host (KDE, or GNOME with the
/// AppIndicator extension), which announces itself on the session bus.
final trayAvailableProvider = FutureProvider<bool>(
  (ref) => TrayController.isSupported(),
);

/// Keeps the tray icon in sync with the "minimize to tray" setting. Kept
/// alive by being watched from the app root.
final trayProvider = Provider<TrayController>((ref) {
  final controller = TrayController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

class TrayController with TrayListener {
  TrayController(this._ref) {
    // While the tray is active, a close request hides the window instead.
    _closeListener = _window.addListener((event) {
      if (event is WindowCloseRequestedEvent && _active) {
        event.request.cancel();
        _enqueue(_hide);
      }
    });
    trayManager.addListener(this);
    _ref.listen<bool>(
      settingsProvider.select((s) => s.minimizeToTray),
      (_, enabled) => _enqueue(() => _apply(enabled)),
      fireImmediately: true,
    );
  }

  static const _keyShow = 'show';
  static const _keyCheck = 'check';
  static const _keyQuit = 'quit';

  final Ref _ref;
  final Window _window = WindowManager.instance.getCurrent()!;
  late final ListenerId _closeListener;
  bool _active = false;
  bool _hintShown = false;
  Future<void> _queue = Future.value();

  void dispose() {
    _window.removeListener(_closeListener);
    trayManager.removeListener(this);
  }

  static Future<bool> isSupported() async {
    if (Platform.isWindows || Platform.isMacOS) return true;
    if (!Platform.isLinux) return false;
    DBusClient? client;
    try {
      client = DBusClient.session();
      return await client.nameHasOwner('org.kde.StatusNotifierWatcher');
    } catch (_) {
      return false;
    } finally {
      await client?.close();
    }
  }

  /// Tray calls must not interleave: the Linux plugin needs the icon before
  /// the menu, and a toggle flipped twice quickly would otherwise race.
  void _enqueue(Future<void> Function() action) {
    _queue = _queue.then((_) => action()).catchError((Object e) {
      _ref
          .read(activityProvider.notifier)
          .warning('Symbolleiste nicht verfügbar: $e', toast: false);
    });
  }

  Future<void> _apply(bool enabled) async {
    final active = enabled && await isSupported();
    if (active == _active) return;
    _active = active;
    if (active) {
      await trayManager.setIcon(_iconAsset);
      if (!Platform.isLinux) await trayManager.setToolTip('WoW Butler');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: _keyShow, label: 'WoW Butler öffnen'),
            MenuItem(key: _keyCheck, label: 'Updates prüfen'),
            MenuItem.separator(),
            MenuItem(key: _keyQuit, label: 'Beenden'),
          ],
        ),
      );
    } else {
      await trayManager.destroy();
      // Never leave the app running without a window to get back to.
      if (!_window.isVisible) await _show();
    }
  }

  static String get _iconAsset {
    if (Platform.isWindows) return 'assets/icon/wow-butler.ico';
    if (Platform.isMacOS) return 'assets/icon/wow-butler-32.png';
    return 'assets/icon/wow-butler-64.png';
  }

  Future<void> _show() async {
    _window
      ..show()
      ..focus();
  }

  Future<void> _hide() async {
    _window.hide();
    if (_hintShown) return;
    _hintShown = true;
    _ref
        .read(activityProvider.notifier)
        .info(
          'WoW Butler läuft in der Symbolleiste weiter. Beenden über das '
          'Menü des Symbols.',
          toast: false,
        );
  }

  Future<void> _checkUpdates() async {
    for (final inst in _ref.read(settingsProvider).installations) {
      await _ref
          .read(addonsProvider(inst.id).notifier)
          .checkUpdates(autoUpdate: true);
    }
  }

  Future<void> _quit() async {
    _active = false;
    await trayManager.destroy();
    // No longer active, so the close request goes through.
    _window.close();
  }

  // -- TrayListener ---------------------------------------------------------

  @override
  void onTrayIconMouseDown() {
    // Windows and macOS only; AppIndicator opens its menu itself.
    _enqueue(_show);
  }

  @override
  void onTrayIconRightMouseDown() {
    _enqueue(trayManager.popUpContextMenu);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _keyShow:
        _enqueue(_show);
      case _keyCheck:
        _enqueue(() async {
          await _show();
          await _checkUpdates();
        });
      case _keyQuit:
        _enqueue(_quit);
    }
  }
}
