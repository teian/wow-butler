import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/storage.dart';
import 'state/providers.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');

  // Frameless window: the app draws its own title bar.
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'WoW Butler',
      size: Size(1260, 800),
      minimumSize: Size(1040, 640),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final support = await getApplicationSupportDirectory();
  final storage = Storage(p.join(support.path, 'data'));
  final settings = await storage.loadSettings();

  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const WowButlerApp(),
    ),
  );
}
