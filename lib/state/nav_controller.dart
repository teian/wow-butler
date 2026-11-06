import 'dart:io';

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
  /// Development aid: `WOW_BUTLER_START_VIEW=browse` opens the app on a
  /// specific top-level page, e.g. for taking screenshots.
  static final AppView? _startView = AppView.values
      .where(
        (v) => v.name == Platform.environment['WOW_BUTLER_START_VIEW'],
      )
      .firstOrNull;

  @override
  NavState build() => NavState(view: _startView ?? AppView.installed);

  void go(AppView view) => state = NavState(view: view);

  void openAddon(String id) =>
      state = NavState(view: AppView.detail, detailId: id);

  void openRemote(RemoteAddon addon) =>
      state = NavState(view: AppView.browseDetail, remote: addon);

  void tab(DetailTab tab) =>
      state = NavState(view: state.view, detailId: state.detailId, tab: tab);
}
