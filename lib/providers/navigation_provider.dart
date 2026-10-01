import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HomeTab { live, lineup, sensors, sessions, settings }

/// Selected bottom-navigation tab, so any screen can switch tabs.
class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.live;

  void go(HomeTab tab) => state = tab;
}

final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);
