import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/addons_controller.dart';
import '../../state/settings_controller.dart';
import '../tokens.dart';
import '../widgets/primitives.dart';

/// Progress of the running update batch, docked above the status bar.
class UpdateQueuePanel extends ConsumerStatefulWidget {
  const UpdateQueuePanel({super.key});

  @override
  ConsumerState<UpdateQueuePanel> createState() => _UpdateQueuePanelState();
}

class _UpdateQueuePanelState extends ConsumerState<UpdateQueuePanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final inst = ref.watch(selectedInstallationProvider)!;
    final state = ref.watch(addonsProvider(inst.id));
    final queue = state.queue;
    if (queue.isEmpty) return const SizedBox.shrink();

    final w = context.w;
    final done = state.queueDone;
    final finished = queue.where((q) => q.finished).length;
    final failed = queue.where((q) => q.stage == QueueStage.failed).length;
    final total =
        queue.fold<double>(0, (sum, q) => sum + q.progress) / queue.length;
    final barColor = !done
        ? WColors.blue
        : failed > 0
        ? WColors.amber
        : WColors.green;

    return Container(
      decoration: BoxDecoration(
        color: w.surface,
        border: Border(top: BorderSide(color: w.border)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 6,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            done
                                ? (failed > 0
                                      ? 'Updates abgeschlossen, $failed fehlgeschlagen'
                                      : 'Updates installiert')
                                : 'Updates werden installiert',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: w.fg,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$finished / ${queue.length}',
                            style: WText.mono(context, size: 12),
                          ),
                        ],
                      ),
                      if (state.backupMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            state.backupMessage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WText.mono(context),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 260,
                  child: WProgress(value: total, height: 6, color: barColor),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(total * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: WText.mono(context, size: 12, color: w.fg),
                  ),
                ),
                const SizedBox(width: 14),
                Hover(
                  onTap: () => setState(() => _expanded = !_expanded),
                  builder: (context, h) => Text(
                    _expanded ? 'Einklappen' : 'Details',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: h ? WColors.blueHover : WColors.blue,
                    ),
                  ),
                ),
                if (done) ...[
                  const SizedBox(width: 8),
                  WIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Schließen',
                    onPressed: () =>
                        ref.read(addonsProvider(inst.id).notifier).clearQueue(),
                  ),
                ],
              ],
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final itemWidth = (c.maxWidth - 28) / 2;
                    return Wrap(
                      spacing: 28,
                      children: [
                        for (final q in queue)
                          SizedBox(
                            width: itemWidth,
                            child: _QueueRow(item: q),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item});

  final QueueItem item;

  @override
  Widget build(BuildContext context) {
    final w = context.w;
    final (String label, Color color) = switch (item.stage) {
      QueueStage.waiting => ('WARTET', w.muted),
      QueueStage.downloading => ('LÄDT', WColors.blue),
      QueueStage.extracting => ('ENTPACKT', WColors.blue),
      QueueStage.done => ('FERTIG', WColors.green),
      QueueStage.failed => ('FEHLER', WColors.red),
    };
    final to = item.toVersion.length > 16
        ? '…${item.toVersion.substring(item.toVersion.length - 10)}'
        : item.toVersion;
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: w.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: w.fg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(to, style: WText.mono(context)),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: WProgress(
              value: item.progress,
              color: item.stage == QueueStage.done
                  ? WColors.green
                  : item.stage == QueueStage.failed
                  ? WColors.red
                  : WColors.blue,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
    return item.error == null ? row : Tooltip(message: item.error!, child: row);
  }
}
