import 'package:flutter_test/flutter_test.dart';
import 'package:pulseboard/models/lineup.dart';
import 'package:pulseboard/utils/rowing_format.dart';

void main() {
  Lineup four() => const Lineup(
    id: 'L',
    name: 'Lineup B',
    boatClass: BoatClass.four,
    seats: ['a', 'b', 'c', 'd'],
    coxId: 'x',
  );

  test('roles: seat 1 is bow, seat n is stroke', () {
    final l = four();
    expect(l.roleOf(1), 'BOW');
    expect(l.roleOf(2), 'SEAT');
    expect(l.roleOf(4), 'STROKE');
    expect(l.seatOf('c'), 3);
  });

  test('a swap moves two people and nobody else', () {
    final l = four().swapSeats(1, 3);
    expect(l.seats, ['c', 'b', 'a', 'd']);
  });

  test('placing a seated rower in another seat swaps them', () {
    final l = four().placeInSeat('a', 4);
    expect(l.seats, ['d', 'b', 'c', 'a']);
    final bench = four().placeInSeat('z', 2);
    expect(bench.seats, ['a', 'z', 'c', 'd']);
  });

  test('changing boat class keeps the bow seats and drops the cox for sculls', () {
    final l = four().copyWith(boatClass: BoatClass.double);
    expect(l.seats, ['a', 'b']);
    expect(l.coxId, isNull);
    final bigger = l.copyWith(boatClass: BoatClass.eight);
    expect(bigger.seats.length, 8);
    expect(bigger.seats.take(2), ['a', 'b']);
  });

  test('prune drops deleted athletes; remove benches one', () {
    expect(four().prune({'a', 'c'}).seats, ['a', null, 'c', null]);
    expect(four().prune({'a'}).coxId, isNull);
    expect(four().remove('b').seats, ['a', null, 'c', 'd']);
    expect(four().remove('x').coxId, isNull);
  });

  test('round-trips through JSON and tolerates junk', () {
    final book = LineupBook(lineups: [four()], activeId: 'L', strokeFirst: false);
    expect(LineupBook.fromJson(book.toJson()), book);
    expect(LineupBook.fromJson('nope'), LineupBook.empty);
    expect(
      LineupBook.fromJson({
        'lineups': [
          42,
          {'id': 1},
        ],
      }).lineups,
      isEmpty,
    );
  });

  group('RowFmt', () {
    test('splits, rates and distances like the SpeedCoach', () {
      expect(RowFmt.split(const Duration(milliseconds: 118400)), '1:58.4');
      expect(RowFmt.split(null), '--:--');
      expect(RowFmt.split(const Duration(milliseconds: 119960)), '2:00.0');
      expect(RowFmt.rate(28.5), '28.5');
      expect(RowFmt.rate(28), '28');
      expect(RowFmt.distance(1240.4), '1,240');
      expect(RowFmt.elapsed(const Duration(milliseconds: 432300)), '7:12.3');
      expect(RowFmt.speed(const Duration(milliseconds: 118200)), '4.23');
      expect(RowFmt.signedSeconds(const Duration(milliseconds: -200)), '−0.2');
    });

    test('parses targets', () {
      expect(RowFmt.parseSplit('1:59.0'), const Duration(seconds: 119));
      expect(RowFmt.parseSplit('1:59'), const Duration(seconds: 119));
      expect(RowFmt.parseSplit('1:75'), isNull);
      expect(RowFmt.parseClock('20:00'), const Duration(minutes: 20));
      expect(RowFmt.parseClock('20'), const Duration(minutes: 20));
      expect(RowFmt.parseClock('x'), isNull);
    });
  });
}
