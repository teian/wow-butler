import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/addon.dart';
import '../core/models/wow_installation.dart';
import 'providers.dart';
import 'settings_controller.dart';

class DiscoverState {
  const DiscoverState({
    this.query = '',
    this.results = const [],
    this.loading = false,
    this.errors = const {},
    this.sourceFilter,
  });

  final String query;
  final List<RemoteAddon> results;
  final bool loading;
  final Map<AddonSourceId, String> errors;

  /// Restricts results to one source; `null` shows all.
  final AddonSourceId? sourceFilter;

  List<RemoteAddon> get visible => sourceFilter == null
      ? results
      : results.where((r) => r.source == sourceFilter).toList();

  DiscoverState copyWith({
    String? query,
    List<RemoteAddon>? results,
    bool? loading,
    Map<AddonSourceId, String>? errors,
    AddonSourceId? sourceFilter,
    bool clearFilter = false,
  }) => DiscoverState(
    query: query ?? this.query,
    results: results ?? this.results,
    loading: loading ?? this.loading,
    errors: errors ?? this.errors,
    sourceFilter: clearFilter ? null : sourceFilter ?? this.sourceFilter,
  );
}

final discoverProvider = NotifierProvider<DiscoverController, DiscoverState>(
  DiscoverController.new,
);

/// Searches all active sources in parallel. An empty query shows each
/// source's featured/popular list.
class DiscoverController extends Notifier<DiscoverState> {
  Timer? _debounce;
  int _generation = 0;

  @override
  DiscoverState build() {
    // Reload when the installation or source configuration changes.
    ref.watch(selectedInstallationProvider.select((i) => (i?.id, i?.flavor)));
    ref.watch(sourcesProvider);
    ref.onDispose(() => _debounce?.cancel());
    Future.microtask(() => _run(''));
    return const DiscoverState(loading: true);
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(query));
  }

  void setFilter(AddonSourceId? source) => state = source == null
      ? state.copyWith(clearFilter: true)
      : state.copyWith(sourceFilter: source);

  Future<void> refresh() => _run(state.query);

  Future<void> _run(String query) async {
    final inst = ref.read(selectedInstallationProvider);
    if (inst == null) {
      state = state.copyWith(loading: false, results: const []);
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(loading: true, errors: const {});
    final q = query.trim();
    final sources = ref.read(sourcesProvider).active;

    final perSource = <AddonSourceId, List<RemoteAddon>>{};
    final errors = <AddonSourceId, String>{};
    await Future.wait(
      sources.map((s) async {
        try {
          perSource[s.id] = q.isEmpty
              ? await s.featured(inst.flavor)
              : await s.search(q, inst.flavor);
        } catch (e) {
          errors[s.id] = '$e';
        }
      }),
    );
    if (generation != _generation || !ref.mounted) return;

    state = state.copyWith(
      loading: false,
      results: _interleave([
        for (final s in sources) perSource[s.id] ?? const <RemoteAddon>[],
      ]),
      errors: errors,
    );
  }

  /// Merges ranked lists round-robin so every source's best hits show up
  /// near the top.
  static List<RemoteAddon> _interleave(List<List<RemoteAddon>> lists) {
    final result = <RemoteAddon>[];
    final seen = <String>{};
    final longest = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (var i = 0; i < longest; i++) {
      for (final list in lists) {
        if (i < list.length && seen.add(list[i].key)) result.add(list[i]);
      }
    }
    return result;
  }
}

/// Picks the release an install button should install: the newest one of
/// the default channel, or any release when the addon has no such build.
AddonRelease? releaseToInstall(RemoteAddon addon, ReleaseChannel channel) =>
    addon.latestFor(channel) ?? addon.latestFor(ReleaseChannel.alpha);
