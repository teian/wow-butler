import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/wow_installation.dart';
import '../../state/addons_controller.dart';
import '../../state/nav_controller.dart';
import '../../state/settings_controller.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';

/// 232px dark sidebar: client switcher, navigation, backups and settings.
class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installations = ref.watch(
      settingsProvider.select((s) => s.installations),
    );
    final selected = ref.watch(selectedInstallationProvider);
    final nav = ref.watch(navProvider);
    final count = selected == null
        ? 0
        : ref.watch(addonsProvider(selected.id).select((s) => s.addons.length));
    final navCtrl = ref.read(navProvider.notifier);

    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: context.w.side,
        border: Border(right: BorderSide(color: context.w.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'WOW-CLIENT',
                    style: WText.caps(WColors.sideLabel),
                  ),
                ),
                for (final inst in installations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _ClientItem(
                      inst: inst,
                      selected: inst.id == selected?.id,
                      onTap: () {
                        ref
                            .read(settingsProvider.notifier)
                            .selectInstallation(inst.id);
                        if (nav.view == AppView.detail) {
                          navCtrl.go(AppView.installed);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: context.w.line,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _NavItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Meine Addons',
                    count: '$count',
                    active:
                        nav.view == AppView.installed ||
                        nav.view == AppView.detail,
                    onTap: () => navCtrl.go(AppView.installed),
                  ),
                  const SizedBox(height: 2),
                  _NavItem(
                    icon: Icons.search_rounded,
                    label: 'Entdecken',
                    active:
                        nav.view == AppView.browse ||
                        nav.view == AppView.browseDetail,
                    onTap: () => navCtrl.go(AppView.browse),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.w.line)),
            ),
            child: Column(
              children: [
                _NavItem(
                  icon: Icons.archive_outlined,
                  label: 'Backups',
                  active: nav.view == AppView.backups,
                  onTap: () => navCtrl.go(AppView.backups),
                ),
                const SizedBox(height: 2),
                _NavItem(
                  icon: Icons.tune_rounded,
                  label: 'Einstellungen',
                  active: nav.view == AppView.settings,
                  onTap: () => navCtrl.go(AppView.settings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientItem extends ConsumerWidget {
  const _ClientItem({
    required this.inst,
    required this.selected,
    required this.onTap,
  });

  final WowInstallation inst;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates = ref.watch(
      addonsProvider(inst.id).select((s) => s.updatable.length),
    );
    return Hover(
      onTap: onTap,
      builder: (context, h) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected || h ? WColors.sideHover : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? WColors.orange : Colors.transparent,
                border: Border.all(
                  color: selected ? WColors.orange : WColors.sideDotBorder,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inst.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WColors.sideText,
                    ),
                  ),
                  Text(
                    inst.gameVersion ?? inst.flavor.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: WFonts.mono,
                      fontSize: 10,
                      color: WColors.sideLabel,
                    ),
                  ),
                ],
              ),
            ),
            if (updates > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: WColors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$updates',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? count;

  @override
  Widget build(BuildContext context) {
    final color = active ? WColors.sideText : WColors.sideMuted;
    return Hover(
      onTap: onTap,
      builder: (context, h) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        decoration: BoxDecoration(
          color: active || h ? WColors.sideHover : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            if (active)
              Positioned(
                left: 0,
                top: 7,
                bottom: 7,
                child: Container(
                  width: 3,
                  decoration: const BoxDecoration(
                    color: WColors.orange,
                    borderRadius: BorderRadius.horizontal(
                      right: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: color,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (count != null)
                    Text(
                      count!,
                      style: const TextStyle(
                        fontFamily: WFonts.mono,
                        fontSize: 11,
                        color: WColors.sideLabel,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
