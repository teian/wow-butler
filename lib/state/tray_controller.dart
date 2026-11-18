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

class TrayController {
  TrayController(this._ref) {
    // While the tray is active, a close request hides the window instead.
    _closeListener = _window.addListener((event) {
      if (event is WindowCloseRequestedEvent && _active) {
        event.request.cancel();
        _enqueue(_hide);
      }
    });
    _ref.listen<bool>(
      settingsProvider.select((s) => s.minimizeToTray),
      (_, enabled) => _enqueue(() => _apply(enabled)),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  final Window _window = WindowManager.instance.getCurrent()!;
  late final ListenerId _closeListener;
  bool _active = false;

  // The icon is removed when its object is released, so keep it. The menu
  // attached to it stays alive natively.
  TrayIcon? _icon;
  bool _hintShown = false;
  Future<void> _queue = Future.value();

  void dispose() {
    _window.removeListener(_closeListener);
    _removeIcon();
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
      try {
        _createIcon();
      } catch (_) {
        // Without an icon there is no way back to a hidden window.
        _active = false;
        _removeIcon();
        rethrow;
      }
    } else {
      _removeIcon();
      // Never leave the app running without a window to get back to.
      if (!_window.isVisible) await _show();
    }
  }

  void _createIcon() {
    final icon = TrayIcon.create();
    final menu = Menu.create();
    if (icon == null || menu == null) {
      throw StateError('Symbol konnte nicht angelegt werden');
    }
    _icon = icon;
    final items = [
      _menuItem('WoW Butler öffnen', _show),
      _menuItem('Updates prüfen', () async {
        await _show();
        await _checkUpdates();
      }),
      _menuItem('Beenden', _quit),
    ];
    menu
      ..addItem(items[0])
      ..addItem(items[1])
      ..addSeparator()
      ..addItem(items[2]);
    icon
      ..icon = ImageAsset.fromAsset(_iconAsset)
      ..setTooltip('WoW Butler')
      ..setContextMenu(menu)
      // On Linux the panel opens the menu itself and reports no clicks.
      ..setContextMenuTrigger(ContextMenuTrigger.rightClicked)
      ..addListener((event) {
        if (event is TrayIconClickedEvent) _enqueue(_show);
      })
      ..setVisible(true);
  }

  MenuItem _menuItem(String label, Future<void> Function() onClick) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) throw StateError('Menü konnte nicht angelegt werden');
    item.addListener((event) {
      if (event is MenuItemClickedEvent) _enqueue(onClick);
    });
    return item;
  }

  void _removeIcon() {
    _icon?.dispose();
    _icon = null;
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
    // The tray may have been switched off while this was queued.
    if (!_active) return;
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
    _removeIcon();
    // No longer active, so the close request goes through.
    _window.close();
  }
}
