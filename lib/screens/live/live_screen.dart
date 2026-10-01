import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/live_theme.dart';
import '../../models/app_settings.dart';
import '../../providers/boat_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import 'boat_data_view.dart';
import 'crew_view.dart';
import 'live_widgets.dart';
import 'ready_view.dart';
import 'simple_view.dart';

/// The Live tab. Before Start it is the ready check; while recording it is
/// the full-screen crew, boat data or simple view on the live palette.
class LiveScreen extends ConsumerWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(activeSessionProvider.select((s) => s != null));
    if (!recording) return const ReadyView();

    final palette = LivePalette.of(ref.watch(settingsProvider.select((s) => s.liveTheme)));
    final mode = ref.watch(liveViewModeProvider);
    final dark = palette.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: LiveScope(
        palette: palette,
        child: Scaffold(
          backgroundColor: palette.bg,
          body: SafeArea(
            child: switch (mode) {
              LiveViewMode.crew => const CrewView(),
              LiveViewMode.boat => const BoatDataView(),
              LiveViewMode.simple => const SimpleView(),
            },
          ),
        ),
      ),
    );
  }
}
