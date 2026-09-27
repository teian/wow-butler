import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/models/app_settings.dart';
import '../../state/settings_controller.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';

/// Custom 40px title bar with drag area, theme toggle and window controls.
class TitleBar extends ConsumerWidget {
  const TitleBar({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 14, right: 10),
      decoration: BoxDecoration(
        color: context.w.side,
        border: Border(bottom: BorderSide(color: context.w.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: WColors.orange,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.download_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'WoW Butler',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.13,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WColors.sideLabel,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
          Tooltip(
            message: 'Theme wechseln',
            child: Hover(
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .update(
                    (s) => s.copyWith(
                      themeMode: isDark
                          ? AppThemeMode.light
                          : AppThemeMode.dark,
                    ),
                  ),
              builder: (context, h) => Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: h ? WColors.sideHover : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
                  size: 16,
                  color: h ? WColors.sideText : WColors.sideMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(width: 1, height: 18, color: WColors.sideHover),
          const SizedBox(width: 12),
          _WindowButton(
            icon: Icons.remove_rounded,
            onTap: () => windowManager.minimize(),
          ),
          const SizedBox(width: 8),
          _WindowButton(
            icon: Icons.crop_square_rounded,
            iconSize: 10,
            onTap: () async => await windowManager.isMaximized()
                ? windowManager.unmaximize()
                : windowManager.maximize(),
          ),
          const SizedBox(width: 8),
          _WindowButton(
            icon: Icons.close_rounded,
            hoverColor: WColors.red,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.hoverColor = const Color(0xFF334155),
    this.iconSize = 11,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color hoverColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Hover(
    onTap: onTap,
    builder: (context, h) => AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: h ? hoverColor : WColors.sideHover,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: iconSize, color: const Color(0xFFCBD5E1)),
    ),
  );
}
