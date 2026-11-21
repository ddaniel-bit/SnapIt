import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:project/game/meme_poses.dart';
import 'package:project/game/play_rules.dart';

void main() {
  test('az idő körről körre rövidül, de nem megy 2 mp alá', () {
    expect(PlayRules.secondsFor(1), 6.0);
    for (var r = 2; r < 40; r++) {
      expect(
        PlayRules.secondsFor(r),
        lessThanOrEqualTo(PlayRules.secondsFor(r - 1)),
      );
      expect(PlayRules.secondsFor(r), greaterThanOrEqualTo(2.0));
    }
    expect(PlayRules.secondsFor(40), 2.0);
  });

  test('a minimum százalék nő, legfeljebb 85%-ig', () {
    expect(PlayRules.minAccuracyFor(1), 35);
    expect(PlayRules.minAccuracyFor(2), 39);
    expect(PlayRules.minAccuracyFor(50), 85);
  });

  test('a mémek keverve jönnek, két egymás utáni sosem ugyanaz', () {
    final deck = MemeDeck(List.of(kMemePoses), rng: math.Random(7));
    var prev = deck.next();
    final seen = {prev};
    for (var i = 0; i < 100; i++) {
      final next = deck.next();
      expect(next, isNot(prev));
      seen.add(next);
      prev = next;
    }
    expect(seen.length, kMemePoses.length);
  });

  test('minden mémnek megvan a képe', () {
    for (final p in kMemePoses) {
      expect(File(p.photo!).existsSync(), isTrue, reason: p.name);
    }
  });

  test('helycserénél a játékosok megtartják a számukat', () {
    final slots = PlayerSlots(2);
    // Az elején balról jobbra: 10-es = P1, 20-as = P2.
    expect(slots.assign([(id: 10, x: 100), (id: 20, x: 500)]), {0: 0, 1: 1});
    // Helyet cserélnek (a lista balról jobbra jön): a számuk marad.
    expect(slots.assign([(id: 20, x: 120), (id: 10, x: 480)]), {1: 0, 0: 1});
  });

  test('aki eltűnik és új azonosítóval jön vissza, a saját helyét kapja', () {
    final slots = PlayerSlots(2);
    slots.assign([(id: 1, x: 100), (id: 2, x: 500)]);
    // P1 (bal) egy pillanatra eltűnik, új követő-azonosítóval tér vissza.
    slots.assign([(id: 2, x: 500)]);
    expect(slots.assign([(id: 7, x: 110), (id: 2, x: 500)]), {0: 0, 1: 1});
  });

  test('több ember, mint játékos: a fölöslegesek nem kapnak helyet', () {
    final slots = PlayerSlots(1);
    expect(slots.assign([(id: 1, x: 100), (id: 2, x: 500)]), {0: 0});
  });
}
