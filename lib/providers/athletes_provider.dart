import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/athlete.dart';
import 'core_providers.dart';

class AthletesController extends Notifier<List<Athlete>> {
  @override
  List<Athlete> build() {
    final repo = ref.watch(athleteRepositoryProvider);
    final sub = repo.changes.listen((list) => state = list);
    ref.onDispose(sub.cancel);
    return ref.read(bootstrapProvider).athletes;
  }

  Future<Athlete> create({
    required String name,
    String? nickname,
    int? age,
    int? maxHrOverride,
    String? notes,
  }) => ref
      .read(athleteRepositoryProvider)
      .create(name: name, nickname: nickname, age: age, maxHrOverride: maxHrOverride, notes: notes);

  Future<void> save(Athlete athlete) => ref.read(athleteRepositoryProvider).update(athlete);

  Future<void> delete(String id) => ref.read(athleteRepositoryProvider).delete(id);
}

final athletesProvider = NotifierProvider<AthletesController, List<Athlete>>(
  AthletesController.new,
);

/// One athlete by id; rebuilds only when that athlete changes.
final athleteByIdProvider = Provider.family<Athlete?, String>((ref, id) {
  return ref.watch(
    athletesProvider.select((list) {
      for (final a in list) {
        if (a.id == id) return a;
      }
      return null;
    }),
  );
});
