import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/addon.dart';
import '../../core/models/wow_installation.dart';
import '../theme.dart';
import '../tokens.dart';

/// Rebuilds [builder] with the hover state of the pointer.
class Hover extends StatefulWidget {
  const Hover({super.key, required this.builder, this.onTap, this.cursor});

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final MouseCursor? cursor;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(context, _hovered);
    return MouseRegion(
      cursor:
          widget.cursor ??
          (widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer),
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.onTap == null
          ? child
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: child,
            ),
    );
  }
}

enum WButtonKind { primary, blue, outline, outlineBlue, danger, ghost }

/// Amber information box, optionally with an action button.
class WNotice extends StatelessWidget {
  const WNotice(this.message, {super.key, this.title, this.action});

  final String message;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: WColors.amber.withValues(alpha: 0.08),
        border: Border.all(color: WColors.amber.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: WColors.amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (title != null)
                    TextSpan(
                      text: '$title  ',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: w.fg,
                      ),
                    ),
                  TextSpan(text: message),
                ],
              ),
              style: TextStyle(fontSize: 12.5, color: w.fg2, height: 1.4),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

class WButton extends StatelessWidget {
  const WButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = WButtonKind.outline,
    this.icon,
    this.trailingIcon,
    this.small = false,
    this.expand = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final WButtonKind kind;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool small;
  final bool expand;

  /// Shown on hover; explains a disabled button, for example.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = _build(context);
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }

  Widget _build(BuildContext context) {
    final w = context.w;
    final enabled = onPressed != null;
    return Hover(
      onTap: onPressed,
      builder: (context, hovered) {
        final h = hovered && enabled;
        final (Color bg, Color fg, Color? border) = switch (kind) {
          WButtonKind.primary => (
            !enabled
                ? WColors.disabled
                : h
                ? WColors.orangeHover
                : WColors.orange,
            Colors.white,
            null,
          ),
          WButtonKind.blue => (
            !enabled
                ? WColors.disabled
                : h
                ? WColors.blueHover
                : WColors.blue,
            Colors.white,
            null,
          ),
          WButtonKind.outline => (h ? w.alt : w.surface, w.fg, w.strong),
          WButtonKind.outlineBlue => (
            h ? WColors.blue : Colors.transparent,
            h ? Colors.white : WColors.blue,
            WColors.blue,
          ),
          WButtonKind.danger => (
            h ? WColors.red.withValues(alpha: 0.08) : w.surface,
            WColors.red,
            w.strong,
          ),
          WButtonKind.ghost => (h ? w.alt : Colors.transparent, w.muted, null),
        };
        final fontSize = small ? 12.0 : 13.0;
        final content = Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: small ? 14 : 15, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.2,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 6),
              Icon(trailingIcon, size: 14, color: fg),
            ],
          ],
        );
        return Opacity(
          opacity:
              enabled || kind == WButtonKind.primary || kind == WButtonKind.blue
              ? 1
              : 0.55,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(
              horizontal: small ? 12 : 16,
              vertical: small ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: border == null ? null : Border.all(color: border),
            ),
            child: content,
          ),
        );
      },
    );
  }
}

/// Square icon button without chrome (title bar, table actions).
class WIconButton extends StatelessWidget {
  const WIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 28,
    this.iconSize = 15,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final button = Hover(
      onTap: onPressed,
      builder: (context, h) => Opacity(
        opacity: h ? 0.7 : 1,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: color ?? context.w.muted),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 34×20 switch.
class WToggle extends StatelessWidget {
  const WToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 20,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value ? WColors.blue : context.w.strong,
              borderRadius: BorderRadius.circular(10),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x4D0F172A),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill segmented control (`Stable | Beta | Alpha`).
class WSegmented<T> extends StatelessWidget {
  const WSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.expand = false,
    this.fontSize = 12,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expand;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    Widget segment((T, String) o) {
      final on = o.$1 == value;
      final child = Hover(
        onTap: () => onChanged(o.$1),
        builder: (context, h) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: on ? w.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            boxShadow: on ? w.shadow : null,
          ),
          child: Text(
            o.$2,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              color: on || h ? w.fg : w.muted,
            ),
          ),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: w.alt,
        border: Border.all(color: w.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            segment(options[i]),
          ],
        ],
      ),
    );
  }
}

class WBadge extends StatelessWidget {
  const WBadge(
    this.label, {
    super.key,
    required this.fg,
    required this.bg,
    this.width,
  });

  final String label;
  final Color fg;
  final Color bg;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      textAlign: width == null ? null : TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: fg,
        height: 1.4,
      ),
    ),
  );
}

class SourceBadge extends StatelessWidget {
  const SourceBadge(
    this.source, {
    super.key,
    this.width,
    this.external = false,
  });

  final AddonSourceId? source;
  final double? width;

  /// Labels a local addon as distributed by subscription or external software.
  final bool external;

  @override
  Widget build(BuildContext context) {
    if (source == null && external) {
      return WBadge(
        'Extern',
        fg: WColors.amber,
        bg: WColors.amber.withValues(alpha: 0.14),
        width: width,
      );
    }
    final c = sourceColors(context, source);
    return WBadge(source?.label ?? 'Lokal', fg: c.fg, bg: c.bg, width: width);
  }
}

/// Status pill with a leading dot (`● UPDATE`).
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  static StatusPill of(BuildContext context, InstalledAddon a) {
    final w = context.w;
    if (!a.isManaged && a.external) {
      return StatusPill(
        'EXTERN',
        fg: WColors.amber,
        bg: WColors.amber.withValues(alpha: 0.14),
      );
    }
    if (!a.isManaged) return StatusPill('LOKAL', fg: w.muted, bg: w.chip);
    if (a.ignored) return StatusPill('IGNORIERT', fg: w.muted, bg: w.chip);
    if (a.pinned) {
      return StatusPill(
        'GEPINNT',
        fg: WColors.blueLight,
        bg: WColors.blueLight.withValues(alpha: 0.14),
      );
    }
    if (a.updateNeedsWebsite) {
      return StatusPill(
        'UPDATE · WEBSITE',
        fg: WColors.amber,
        bg: WColors.amber.withValues(alpha: 0.14),
      );
    }
    if (!a.downloadsAllowed) {
      return StatusPill('NUR WEBSITE', fg: w.muted, bg: w.chip);
    }
    if (a.hasUpdate) {
      return StatusPill(
        'UPDATE',
        fg: WColors.orange,
        bg: WColors.orange.withValues(alpha: 0.12),
      );
    }
    return StatusPill(
      'AKTUELL',
      fg: WColors.green,
      bg: WColors.green.withValues(alpha: 0.14),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: fg,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class ChannelPill extends StatelessWidget {
  const ChannelPill(this.channel, {super.key});

  final ReleaseChannel channel;

  @override
  Widget build(BuildContext context) {
    final color = switch (channel) {
      ReleaseChannel.stable => WColors.green,
      ReleaseChannel.beta => WColors.blueLight,
      ReleaseChannel.alpha => WColors.amber,
    };
    return WBadge(
      channel.label.toUpperCase(),
      fg: color,
      bg: color.withValues(alpha: 0.14),
    );
  }
}

class WCheckbox extends StatelessWidget {
  const WCheckbox({
    super.key,
    required this.checked,
    this.onTap,
    this.size = 16,
  });

  final bool checked;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: checked ? WColors.blue : w.surface,
            border: Border.all(color: checked ? WColors.blue : w.strong),
            borderRadius: BorderRadius.circular(4),
          ),
          child: checked
              ? Icon(Icons.check_rounded, size: size - 4, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class WCard extends StatelessWidget {
  const WCard({super.key, required this.child, this.padding, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? w.surface,
        border: Border.all(color: w.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: w.shadow,
      ),
      child: child,
    );
  }
}

class WProgress extends StatelessWidget {
  const WProgress({
    super.key,
    required this.value,
    this.height = 4,
    this.color,
  });

  final double? value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: LinearProgressIndicator(
      value: value,
      minHeight: height,
      color: color ?? WColors.blue,
      backgroundColor: context.w.track,
    ),
  );
}

/// Text input with the design's border and optional leading search icon.
class WInput extends StatelessWidget {
  const WInput({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.search = false,
    this.mono = false,
    this.obscure = false,
    this.fontSize = 13,
    this.focusNode,
    this.suffix,
  });

  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool search;
  final bool mono;
  final bool obscure;
  final double fontSize;
  final FocusNode? focusNode;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: w.strong),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      obscureText: obscure,
      style: TextStyle(
        fontFamily: mono ? WFonts.mono : WFonts.sans,
        fontSize: mono ? 12 : fontSize,
        color: w.fg,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: w.surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: search ? 0 : 10,
          vertical: search ? 10 : 9,
        ),
        prefixIcon: search
            ? Icon(Icons.search_rounded, size: 16, color: w.muted)
            : null,
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        suffixIcon: suffix,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: WColors.blue),
        ),
      ),
    );
  }
}

/// Square tile with the addon logo or its initials in mono.
class InitialsTile extends StatelessWidget {
  const InitialsTile({super.key, required this.name, this.url, this.size = 34});

  final String name;
  final String? url;
  final double size;

  static String initials(String name) {
    final words = name
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2);
    final text = words.map((w) => w[0]).join().toUpperCase();
    return text.isEmpty ? '?' : text;
  }

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final radius = size >= 56 ? 8.0 : 6.0;
    final fallback = Center(
      child: Text(
        initials(name),
        style: TextStyle(
          fontFamily: WFonts.mono,
          fontSize: size >= 56 ? 16 : (size >= 40 ? 12 : 11),
          fontWeight: FontWeight.w600,
          color: w.fg2,
        ),
      ),
    );
    final u = url;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: w.alt,
        border: Border.all(color: w.border),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: u == null || u.isEmpty
          ? fallback
          : Image.network(
              u,
              fit: BoxFit.cover,
              cacheWidth: (size * 2).round(),
              errorBuilder: (_, _, _) => fallback,
              frameBuilder: (_, child, frame, sync) =>
                  frame == null && !sync ? fallback : child,
            ),
    );
  }
}

/// Setting row: label + hint on the left, control on the right.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.hint,
    this.trailing,
    this.top = true,
    this.labelSize = 14,
  });

  final String label;
  final String? hint;
  final Widget? trailing;
  final bool top;
  final double labelSize;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: top ? Border(top: BorderSide(color: w.border)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: labelSize,
                    fontWeight: FontWeight.w500,
                    color: w.fg,
                  ),
                ),
                if (hint != null) Text(hint!, style: WText.muted(context)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

/// Card with a title block and rows separated by borders.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.children = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => WCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: WText.cardTitle(context)),
                    if (subtitle != null)
                      Text(subtitle!, style: WText.muted(context)),
                  ],
                ),
              ),
              for (final a in actions) ...[const SizedBox(width: 8), a],
            ],
          ),
        ),
        ...children,
      ],
    ),
  );
}

/// Monospace path shown in a tinted box.
class PathChip extends StatelessWidget {
  const PathChip(this.path, {super.key});

  final String path;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: context.w.alt,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      path,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: WText.mono(context, color: context.w.fg2),
    ),
  );
}

/// How an installation is run, derived from its path (shown as a badge).
String installVia(WowInstallation inst) {
  final path = inst.clientPath.replaceAll(r'\', '/').toLowerCase();
  if (path.contains('/compatdata/')) return 'PROTON';
  if (path.contains('bottles')) return 'BOTTLES';
  if (path.contains('/.wine/')) return 'WINE';
  if (path.contains('/drive_c/')) return 'LUTRIS';
  return 'NATIV';
}

/// Opens [url] in the system default browser.
Future<void> openUrl(String? url) async {
  if (url == null || url.isEmpty) return;
  await _openExternal(Uri.parse(url));
}

/// Opens [path] in the system file manager.
Future<void> openFolder(String path) => _openExternal(Uri.file(path));

/// On Linux `xdg-open` honours the desktop's default applications (it
/// delegates to kde-open, gio, ... per desktop). url_launcher goes through
/// GIO directly, which ignores e.g. the browser chosen in KDE's settings.
Future<void> _openExternal(Uri uri) async {
  if (Platform.isLinux) {
    try {
      await Process.start('xdg-open', [
        uri.toString(),
      ], mode: ProcessStartMode.detached);
      return;
    } on ProcessException {
      // xdg-utils missing: fall back to url_launcher.
    }
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        WButton(
          label: 'Abbrechen',
          onPressed: () => Navigator.pop(context, false),
        ),
        WButton(
          label: confirmLabel,
          kind: destructive ? WButtonKind.danger : WButtonKind.blue,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return result ?? false;
}
