import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/live_theme.dart';
import '../../models/lineup.dart';
import '../../providers/athletes_provider.dart';
import '../../providers/lineup_provider.dart';
import 'live_widgets.dart';

/// Swap two rowers mid-session: tap a rower, tap a seat, confirm. A swap
/// moves two people and nobody else; straps follow their athletes. No
/// dragging on the water: wet hands and a bouncing launch make drags error
/// prone.
Future<void> showSeatsSheet(BuildContext context, {required LivePalette palette}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.brightness == Brightness.dark ? const Color(0xFF151B20) : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => LiveScope(palette: palette, child: const _SeatsSheet()),
  );
}

class _SeatsSheet extends ConsumerStatefulWidget {
  const _SeatsSheet();

  @override
  ConsumerState<_SeatsSheet> createState() => _SeatsSheetState();
}

class _SeatsSheetState extends ConsumerState<_SeatsSheet> {
  int? _from;
  int? _to;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final lineup = ref.watch(activeLineupProvider);
    final strokeFirst = ref.watch(lineupBookProvider.select((b) => b.strokeFirst));
    final names = {for (final a in ref.watch(athletesProvider)) a.id: a.displayName};
    if (lineup == null) return const SizedBox(height: 200);

    String nameAt(int n) {
      final id = lineup.seats[n - 1];
      return id == null ? 'Empty' : (names[id] ?? 'Unknown');
    }

    final order = [for (var n = 1; n <= lineup.seatCount; n++) n];
    final seats = strokeFirst ? order.reversed.toList() : order;
    final from = _from;
    final to = _to;
    final fromName = from == null ? null : nameAt(from);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: p.lo, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              from == null ? 'Swap seats' : 'Move $fromName',
              style: LiveType.body(24, p.hi, weight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              from == null
                  ? 'Tap the rower to move.'
                  : 'Now in seat $from. Their strap moves with them. Tap a seat to swap.',
              style: LiveType.body(15, p.mid, weight: FontWeight.w500),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: lineup.seatCount >= 4 ? 4 : lineup.seatCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.15,
              children: [
                for (final n in seats)
                  _SeatButton(
                    seat: n,
                    name: nameAt(n),
                    tag: n == from
                        ? 'NOW'
                        : n == to
                        ? 'SWAP'
                        : (lineup.roleOf(n) == 'SEAT' ? '' : lineup.roleOf(n)),
                    state: n == from
                        ? _SeatState.from
                        : n == to
                        ? _SeatState.to
                        : _SeatState.idle,
                    onTap: () => setState(() {
                      if (from == null || n == from) {
                        _from = n == from ? null : n;
                        _to = null;
                      } else {
                        _to = n;
                      }
                    }),
                  ),
              ],
            ),
            if (from != null && to != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: p.aheadBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${nameAt(from)} → seat $to\n${nameAt(to)} → seat $from',
                  style: LiveType.body(15, p.ahead, weight: FontWeight.w700),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 10,
                    child: LiveButton(
                      icon: Icons.event_seat_outlined,
                      label: 'To bench',
                      vertical: false,
                      fontSize: 15,
                      onPressed: from == null || lineup.seats[from - 1] == null
                          ? null
                          : () => _bench(lineup, from),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 10,
                    child: LiveButton(
                      icon: Icons.close,
                      label: 'Cancel',
                      vertical: false,
                      fontSize: 15,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 13,
                    child: LiveButton(
                      icon: Icons.swap_vert,
                      label: 'Swap seats',
                      vertical: false,
                      fontSize: 17,
                      background: from != null && to != null ? p.primary : p.btn,
                      color: from != null && to != null ? p.onPrimary : p.lo,
                      onPressed: from != null && to != null ? () => _swap(lineup, from, to) : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _swap(Lineup lineup, int a, int b) async {
    await ref.read(lineupBookProvider.notifier).save(lineup.swapSeats(a, b));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _bench(Lineup lineup, int seat) async {
    final id = lineup.seats[seat - 1];
    if (id == null) return;
    await ref.read(lineupBookProvider.notifier).save(lineup.remove(id));
    if (mounted) Navigator.pop(context);
  }
}

enum _SeatState { idle, from, to }

class _SeatButton extends StatelessWidget {
  const _SeatButton({
    required this.seat,
    required this.name,
    required this.tag,
    required this.state,
    required this.onTap,
  });

  final int seat;
  final String name;
  final String tag;
  final _SeatState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = LiveScope.of(context);
    final (border, bg, tagColor) = switch (state) {
      _SeatState.from => (BorderSide(color: p.lo, width: 2), p.tile, p.mid),
      _SeatState.to => (BorderSide(color: p.ahead, width: 3), p.aheadBg, p.ahead),
      _SeatState.idle => (BorderSide(color: p.line), p.btn, p.lo),
    };
    return Semantics(
      button: true,
      selected: state != _SeatState.idle,
      label: 'Seat $seat, $name${tag.isEmpty ? '' : ', $tag'}',
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: border),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$seat', style: LiveType.number(24, p.hi)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        tag,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: LiveType.label(10, tagColor, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LiveType.body(13, p.hi),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
