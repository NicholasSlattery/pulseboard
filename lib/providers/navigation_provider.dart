import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HomeTab { dashboard, sensors, athletes, sessions, settings }

/// Selected bottom-navigation tab, so any screen can switch tabs.
class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.dashboard;

  void go(HomeTab tab) => state = tab;
}

final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);
