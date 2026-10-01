import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/athlete.dart';
import '../../models/lineup.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/lineup_provider.dart';
import '../../providers/session_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import '../../widgets/strap_status.dart';
import '../athletes/athletes_screen.dart';

/// Boat class, saved lineups, seat order and the bench. Edits are a draft
/// until Save; moved rowers show "was N" until then.
class LineupScreen extends ConsumerStatefulWidget {
  const LineupScreen({super.key});

  @override
  ConsumerState<LineupScreen> createState() => _LineupScreenState();
}

class _LineupScreenState extends ConsumerState<LineupScreen> {
  Lineup? _draft;

  void _edit(Lineup next) => setState(() => _draft = next);

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    await ref.read(lineupBookProvider.notifier).save(draft);
    if (!mounted) return;
    setState(() => _draft = null);
    showSnack(
      context,
      ref.read(activeSessionProvider) != null
          ? 'Lineup saved. Seat changes are logged with the session.'
          : 'Lineup saved',
    );
  }

  Future<void> _newLineup() async {
    final name = await _askName(context, title: 'New lineup', initial: _nextName());
    if (name == null) return;
    final boat = _draft?.boatClass ?? ref.read(activeLineupProvider)?.boatClass;
    await ref.read(lineupBookProvider.notifier).create(name: name, boatClass: boat);
    setState(() => _draft = null);
  }

  String _nextName() {
    final count = ref.read(lineupBookProvider).lineups.length;
    return 'Lineup ${String.fromCharCode(65 + count % 26)}';
  }

  Future<void> _pickLineup() async {
    final book = ref.read(lineupBookProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final l in book.lineups)
              ListTile(
                leading: Icon(
                  l.id == book.active?.id ? Icons.radio_button_checked : Icons.radio_button_off,
                ),
                title: Text(l.name),
                subtitle: Text(
                  '${l.boatClass.label} · ${l.athleteIds.length} of ${l.seatCount} seats filled',
                ),
                onTap: () => Navigator.pop(context, l.id),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New lineup'),
              onTap: () => Navigator.pop(context, '+'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == '+') return _newLineup();
    if (_draft != null && _draft!.id != picked) {
      final discard = await confirmAction(
        context,
        title: 'Discard changes?',
        message: 'The unsaved seat changes to this lineup will be lost.',
        confirmLabel: 'Discard',
      );
      if (!discard) return;
    }
    setState(() => _draft = null);
    await ref.read(lineupBookProvider.notifier).select(picked);
  }

  Future<void> _lineupMenu(Lineup saved, String action) async {
    switch (action) {
      case 'rename':
        final name = await _askName(context, title: 'Rename lineup', initial: saved.name);
        if (name == null) return;
        await ref.read(lineupBookProvider.notifier).save(saved.copyWith(name: name));
        if (_draft != null) setState(() => _draft = _draft!.copyWith(name: name));
      case 'delete':
        final ok = await confirmAction(
          context,
          title: 'Delete ${saved.name}?',
          message: 'Athletes and their straps are kept. Only this seat order is removed.',
          confirmLabel: 'Delete',
        );
        if (!ok) return;
        setState(() => _draft = null);
        await ref.read(lineupBookProvider.notifier).delete(saved.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(activeLineupProvider);
    final athletes = ref.watch(athletesProvider);
    final strokeFirst = ref.watch(lineupBookProvider.select((b) => b.strokeFirst));
    final theme = Theme.of(context);

    if (_draft != null && _draft!.id != saved?.id) _draft = null;
    final lineup = _draft ?? saved;
    final dirty = _draft != null && _draft != saved;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lineup'),
        actions: [
          if (saved != null)
            PopupMenuButton<String>(
              tooltip: 'Lineup options',
              onSelected: (a) => _lineupMenu(saved, a),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename lineup')),
                PopupMenuItem(value: 'delete', child: Text('Delete lineup')),
              ],
            ),
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AthletesScreen())),
            icon: const Icon(Icons.groups_outlined),
            label: const Text('Athletes'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: lineup == null
          ? EmptyState(
              icon: Icons.format_list_numbered,
              title: 'No lineup yet',
              message: athletes.isEmpty
                  ? 'Add your athletes first, then set who sits in which seat. The live '
                        'screen shows the crew in seat order.'
                  : 'Set who sits in which seat. The live screen shows the crew in seat '
                        'order, and straps follow their rowers.',
              action: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => ref.read(lineupBookProvider.notifier).ensureActive(),
                    icon: const Icon(Icons.add),
                    label: const Text('Create lineup'),
                  ),
                  if (athletes.isEmpty)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => const AthletesScreen())),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Add athletes'),
                    ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _Editor(
                    lineup: lineup,
                    saved: saved!,
                    athletes: athletes,
                    strokeFirst: strokeFirst,
                    onChanged: _edit,
                    onPickLineup: _pickLineup,
                    onNewLineup: _newLineup,
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'During a session, seat changes apply to the live screen right away '
                          'and are logged with the time and distance.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (dirty) ...[
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                                    onPressed: () => setState(() => _draft = null),
                                    child: const Text('Discard'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 52,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    shape: const StadiumBorder(),
                                    textStyle: Theme.of(
                                      context,
                                    ).textTheme.titleMedium?.copyWith(fontSize: 17),
                                  ),
                                  onPressed: dirty ? _save : null,
                                  child: Text(dirty ? 'Save lineup' : 'Saved'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Editor extends ConsumerWidget {
  const _Editor({
    required this.lineup,
    required this.saved,
    required this.athletes,
    required this.strokeFirst,
    required this.onChanged,
    required this.onPickLineup,
    required this.onNewLineup,
  });

  final Lineup lineup;
  final Lineup saved;
  final List<Athlete> athletes;
  final bool strokeFirst;
  final ValueChanged<Lineup> onChanged;
  final VoidCallback onPickLineup;
  final VoidCallback onNewLineup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final byId = {for (final a in athletes) a.id: a};
    final bench = [
      for (final a in athletes)
        if (!lineup.contains(a.id)) a,
    ]..sort((a, b) => naturalCompare(a.displayName, b.displayName));

    // Display order: stroke at the top unless Bow first.
    final order = [for (var n = 1; n <= lineup.seatCount; n++) n];
    final display = strokeFirst ? order.reversed.toList() : order;

    void reorder(int oldIndex, int newIndex) {
      final people = [for (final n in display) lineup.seats[n - 1]];
      final moved = people.removeAt(oldIndex);
      people.insert(newIndex, moved);
      final seats = List<String?>.filled(lineup.seatCount, null);
      for (var i = 0; i < display.length; i++) {
        seats[display[i] - 1] = people[i];
      }
      onChanged(lineup.copyWith(seats: seats));
    }

    Future<void> chooseFor(int seat) async {
      final picked = await _pickAthlete(
        context,
        title: 'Seat $seat',
        athletes: [...bench, for (final id in lineup.athleteIds) byId[id]!],
        current: lineup.seats[seat - 1],
        lineup: lineup,
      );
      if (picked == null) return;
      onChanged(lineup.placeInSeat(picked.isEmpty ? null : picked, seat));
    }

    Future<void> chooseCox() async {
      final picked = await _pickAthlete(
        context,
        title: 'Cox',
        athletes: bench,
        current: lineup.coxId,
        lineup: lineup,
      );
      if (picked == null) return;
      onChanged(lineup.copyWith(coxId: () => picked.isEmpty ? null : picked));
    }

    void addFromBench(Athlete a) {
      final empty = lineup.seats.indexOf(null);
      if (empty >= 0) {
        onChanged(lineup.placeInSeat(a.id, empty + 1));
      } else if (lineup.boatClass.cox && lineup.coxId == null) {
        onChanged(lineup.copyWith(coxId: () => a.id));
      } else {
        showSnack(context, 'Every seat is taken. Use ⋮ on a seat to swap ${a.displayName} in.');
      }
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          sliver: SliverList.list(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onPickLineup,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Saved lineup',
                          suffixIcon: Icon(Icons.expand_more),
                        ),
                        child: Text(
                          '${lineup.boatClass.label} · ${lineup.name}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton.filledTonal(
                      tooltip: 'New lineup',
                      onPressed: onNewLineup,
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<BoatClass>(
                segments: [
                  for (final b in BoatClass.values) ButtonSegment(value: b, label: Text(b.label)),
                ],
                selected: {lineup.boatClass},
                showSelectedIcon: false,
                onSelectionChanged: (v) => onChanged(lineup.copyWith(boatClass: v.first)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Live screen order',
                      style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Stroke first')),
                      ButtonSegment(value: false, label: Text('Bow first')),
                    ],
                    selected: {strokeFirst},
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    onSelectionChanged: (v) =>
                        ref.read(lineupBookProvider.notifier).setStrokeFirst(v.first),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('SEATS', style: _sectionStyle(theme))),
                  Text(
                    'Drag ≡ to reorder',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (lineup.boatClass.cox) ...[
                _CoxRow(
                  athlete: lineup.coxId == null ? null : byId[lineup.coxId],
                  onTap: chooseCox,
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverReorderableList(
            itemCount: display.length,
            onReorderItem: reorder,
            itemBuilder: (context, i) {
              final n = display[i];
              final id = lineup.seats[n - 1];
              final was = id == null ? null : saved.seatOf(id);
              return Padding(
                key: ValueKey('seat-$n-${id ?? 'empty'}'),
                padding: const EdgeInsets.only(bottom: 6),
                child: _SeatRow(
                  index: i,
                  seat: n,
                  role: lineup.roleOf(n),
                  athlete: id == null ? null : byId[id],
                  movedFrom: was != null && was != n ? was : null,
                  isNew: id != null && was == null,
                  onTap: () => chooseFor(n),
                  onBench: id == null ? null : () => onChanged(lineup.remove(id)),
                ),
              );
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          sliver: SliverList.list(
            children: [
              Text('NOT IN THE BOAT', style: _sectionStyle(theme)),
              const SizedBox(height: 8),
              if (bench.isEmpty)
                Text(
                  athletes.isEmpty
                      ? 'No athletes yet. Add them with Athletes above.'
                      : 'Everyone is in the boat.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in bench)
                      ActionChip(
                        avatar: Icon(Icons.add, color: scheme.primary),
                        label: Text(a.displayName),
                        onPressed: () => addFromBench(a),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  static TextStyle? _sectionStyle(ThemeData theme) => theme.textTheme.labelLarge?.copyWith(
    letterSpacing: 0.8,
    color: theme.colorScheme.onSurfaceVariant,
  );
}

class _CoxRow extends StatelessWidget {
  const _CoxRow({required this.athlete, required this.onTap});

  final Athlete? athlete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _RowShell(
      onTap: onTap,
      children: [
        const SizedBox(width: 48),
        _SeatLabel(number: 'C', role: 'COX', color: scheme.onSurfaceVariant),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                athlete?.displayName ?? 'No cox',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: athlete == null ? scheme.onSurfaceVariant : null,
                ),
              ),
              Text(
                athlete == null ? 'Tap to choose' : 'HR not shown on the live screen',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 48, child: Icon(Icons.chevron_right)),
      ],
    );
  }
}

class _SeatRow extends ConsumerWidget {
  const _SeatRow({
    required this.index,
    required this.seat,
    required this.role,
    required this.athlete,
    required this.movedFrom,
    required this.isNew,
    required this.onTap,
    required this.onBench,
  });

  final int index;
  final int seat;
  final String role;
  final Athlete? athlete;
  final int? movedFrom;
  final bool isNew;
  final VoidCallback onTap;
  final VoidCallback? onBench;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = athlete;
    final strap = a == null ? null : watchStrapStatus(ref, a.id);
    final moved = movedFrom != null ? 'was $movedFrom' : (isNew ? 'new' : null);
    return _RowShell(
      onTap: onTap,
      dashed: a == null,
      children: [
        ReorderableDragStartListener(
          index: index,
          child: Semantics(
            label: 'Drag to reorder seat $seat',
            child: const SizedBox(width: 48, height: 48, child: Icon(Icons.drag_handle)),
          ),
        ),
        _SeatLabel(number: '$seat', role: role, color: scheme.primary),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      a?.displayName ?? 'Empty seat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: a == null ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                  ),
                  if (moved != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      moved,
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (strap != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: strap.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      strap?.description ?? 'Tap to choose a rower',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Seat $seat options',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == 'choose') onTap();
            if (v == 'bench') onBench?.call();
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'choose', child: Text(a == null ? 'Choose rower' : 'Swap rower')),
            if (onBench != null) const PopupMenuItem(value: 'bench', child: Text('Move to bench')),
          ],
        ),
      ],
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({required this.children, required this.onTap, this.dashed = false});

  final List<Widget> children;
  final VoidCallback onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: dashed ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: dashed ? scheme.outline : scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(height: 64, child: Row(children: [...children, const SizedBox(width: 4)])),
      ),
    );
  }
}

class _SeatLabel extends StatelessWidget {
  const _SeatLabel({required this.number, required this.role, required this.color});

  final String number;
  final String role;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            number,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, height: 1, color: color),
          ),
          Text(
            role,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.8,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks an athlete. Resolves to the id, '' for "leave empty", or null when
/// cancelled.
Future<String?> _pickAthlete(
  BuildContext context, {
  required String title,
  required List<Athlete> athletes,
  required String? current,
  required Lineup lineup,
}) {
  final sorted = [...athletes]..sort((a, b) => naturalCompare(a.displayName, b.displayName));
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.event_seat_outlined),
              title: const Text('Leave empty'),
              onTap: () => Navigator.pop(context, ''),
            ),
          if (sorted.isEmpty)
            const ListTile(title: Text('No athletes to choose. Add them with Athletes.')),
          for (final a in sorted)
            ListTile(
              leading: Icon(a.id == current ? Icons.check_circle : Icons.person_outline),
              title: Text(a.displayName),
              subtitle: lineup.seatOf(a.id) == null
                  ? const Text('Not in the boat')
                  : Text('Now in seat ${lineup.seatOf(a.id)}: they swap'),
              onTap: () => Navigator.pop(context, a.id),
            ),
        ],
      ),
    ),
  );
}

Future<String?> _askName(BuildContext context, {required String title, required String initial}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            Navigator.pop(context, v.isEmpty ? null : v);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
