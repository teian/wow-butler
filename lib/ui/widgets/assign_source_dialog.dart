import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/addon.dart';
import '../../core/models/wow_installation.dart';
import '../../state/addons_controller.dart';
import '../../state/providers.dart';
import '../tokens.dart';
import 'primitives.dart';

/// Searches the active sources and links the picked result to [addon],
/// without reinstalling anything.
Future<void> showAssignSourceDialog(
  BuildContext context, {
  required WowInstallation inst,
  required InstalledAddon addon,
}) => showDialog(
  context: context,
  builder: (_) => _AssignSourceDialog(inst: inst, addon: addon),
);

class _AssignSourceDialog extends ConsumerStatefulWidget {
  const _AssignSourceDialog({required this.inst, required this.addon});

  final WowInstallation inst;
  final InstalledAddon addon;

  @override
  ConsumerState<_AssignSourceDialog> createState() =>
      _AssignSourceDialogState();
}

class _AssignSourceDialogState extends ConsumerState<_AssignSourceDialog> {
  late final _controller = TextEditingController(text: widget.addon.name);
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  List<RemoteAddon> _results = const [];

  @override
  void initState() {
    super.initState();
    _search(_controller.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    final generation = ++_generation;
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _loading = true);
    final sources = ref.read(sourcesProvider).active;
    final perSource = await Future.wait(
      sources.map((s) async {
        try {
          return await s.search(q, widget.inst.flavor);
        } on Object {
          return const <RemoteAddon>[];
        }
      }),
    );
    if (!mounted || generation != _generation) return;
    final seen = <String>{};
    setState(() {
      _loading = false;
      _results = [
        for (final list in perSource)
          for (final r in list.take(10))
            if (seen.add(r.key)) r,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    return Dialog(
      backgroundColor: w.surface,
      child: Container(
        width: 540,
        height: 520,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quelle zuordnen',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: w.fg,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '„${widget.addon.name}" wird mit dem gewählten Treffer '
              'verknüpft – ohne Neuinstallation.',
              style: TextStyle(fontSize: 12, color: w.muted),
            ),
            const SizedBox(height: 12),
            WInput(
              controller: _controller,
              hint: 'Suche in allen aktiven Quellen…',
              search: true,
              onChanged: _onChanged,
              onSubmitted: _search,
            ),
            const SizedBox(height: 4),
            Text(
              'GitHub-Addons: owner/repo oder Repository-URL einfügen.',
              style: TextStyle(fontSize: 11, color: w.muted),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        'Keine Treffer.',
                        style: TextStyle(fontSize: 13, color: w.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) =>
                          _resultRow(context, _results[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(BuildContext context, RemoteAddon remote) {
    final w = context.w;
    return Hover(
      onTap: () async {
        final navigator = Navigator.of(context);
        await ref
            .read(addonsProvider(widget.inst.id).notifier)
            .assignSource(widget.addon, remote);
        if (mounted) navigator.pop();
      },
      builder: (context, h) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: h ? w.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SourceBadge(remote.source, width: 84),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    remote.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: w.fg,
                    ),
                  ),
                  if (remote.author != null)
                    Text(
                      remote.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: w.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              remote.latestFor(widget.addon.channel)?.version ??
                  remote.releases.firstOrNull?.version ??
                  '—',
              style: TextStyle(fontSize: 12, color: w.muted),
            ),
          ],
        ),
      ),
    );
  }
}
