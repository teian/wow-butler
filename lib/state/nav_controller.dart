import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/addon.dart';

enum AppView {
  installed,
  browse,
  detail,
  browseDetail,
  backups,
  settings,
  onboarding,
}

enum DetailTab { overview, changelog, versions }

class NavState {
  const NavState({
    this.view = AppView.installed,
    this.detailId,
    this.tab = DetailTab.overview,
    this.remote,
  });

  final AppView view;
  final String? detailId;
  final DetailTab tab;

  /// Addon shown in [AppView.browseDetail].
  final RemoteAddon? remote;
}

final navProvider = NotifierProvider<NavController, NavState>(
  NavController.new,
);

class NavController extends Notifier<NavState> {
  @override
  NavState build() => const NavState();

  void go(AppView view) => state = NavState(view: view);

  void openAddon(String id) =>
      state = NavState(view: AppView.detail, detailId: id);

  void openRemote(RemoteAddon addon) =>
      state = NavState(view: AppView.browseDetail, remote: addon);

  void tab(DetailTab tab) =>
      state = NavState(view: state.view, detailId: state.detailId, tab: tab);
}
