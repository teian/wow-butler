import 'dart:async';
import 'dart:collection';
import 'dart:math';

/// Runs at most [limit] tasks at the same time; further tasks wait in order.
/// The limit is read again whenever a task starts, so a changed setting
/// applies to the next tasks.
class Limiter {
  Limiter(this.limit);

  final int Function() limit;
  int _running = 0;
  final _waiting = Queue<Completer<void>>();

  int get running => _running;

  Future<T> run<T>(Future<T> Function() task) async {
    while (_running >= max(1, limit())) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      // Wake every waiter a free slot exists for (the limit may have grown).
      var free = max(1, limit()) - _running;
      while (free-- > 0 && _waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      }
    }
  }
}
