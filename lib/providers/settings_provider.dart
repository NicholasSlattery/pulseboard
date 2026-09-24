import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import 'core_providers.dart';

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(bootstrapProvider).settings;

  Future<void> save(AppSettings next) async {
    if (next == state) return;
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }

  Future<void> edit(AppSettings Function(AppSettings current) change) => save(change(state));
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
