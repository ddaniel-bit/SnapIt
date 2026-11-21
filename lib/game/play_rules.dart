import 'dart:math' as math;

import 'target_pose.dart';

/// A játékmód szabályai: körről körre rövidül az idő, és nő a minimum
/// pontosság, amit el kell érni.
class PlayRules {
  const PlayRules._();

  /// Ennyi ideig látszik a mém nagyban, mielőtt a sarokba megy.
  static const Duration showMemeFor = Duration(milliseconds: 1500);

  static const double startSeconds = 6.0;
  static const double timeFactor = 0.88;
  static const double minSeconds = 2.0;

  static const double startMinAccuracy = 35;
  static const double minAccuracyStep = 4;
  static const double maxMinAccuracy = 85;

  /// Ennyi idő jut a pózra az adott körben (1-től számolva).
  static double secondsFor(int round) => math.max(
    minSeconds,
    startSeconds * math.pow(timeFactor, round - 1).toDouble(),
  );

  /// Legalább ennyi százalék kell a továbbjutáshoz az adott körben.
  static double minAccuracyFor(int round) => math.min(
    maxMinAccuracy,
    startMinAccuracy + minAccuracyStep * (round - 1),
  );
}

/// A mémek sorrendje: keverve jönnek, és ha mind elfogyott, újrakeveri –
/// úgy, hogy két egymás utáni kör ne ugyanaz legyen.
class MemeDeck {
  MemeDeck(this.poses, {math.Random? rng}) : _rng = rng ?? math.Random();

  final List<TargetPose> poses;
  final math.Random _rng;
  final List<TargetPose> _queue = [];
  TargetPose? _last;

  TargetPose next() {
    if (_queue.isEmpty) {
      _queue.addAll(poses..shuffle(_rng));
      if (_queue.length > 1 && _queue.first == _last) {
        _queue.add(_queue.removeAt(0));
      }
    }
    return _last = _queue.removeAt(0);
  }
}

/// Versenyben a játékosok (P1, P2, …) a követő azonosítójához kötve, hogy
/// ha helyet cserélnek, a pontszámuk ne cserélődjön fel. Új követett ember a
/// legutóbbi helyéhez legközelebbi szabad játékoshelyet kapja (az elején
/// balról jobbra P1, P2, …).
class PlayerSlots {
  PlayerSlots(this.count) : _lastX = List.filled(count, null);

  final int count;
  final Map<int, int> _slotOf = {};
  final List<double?> _lastX;

  /// [people]: a képen lévők (követő-azonosító, vízszintes hely), balról
  /// jobbra. Eredmény: játékoshely → index a [people] listában.
  Map<int, int> assign(List<({int id, double x})> people) {
    final result = <int, int>{};
    final taken = <int>{};
    for (var i = 0; i < people.length; i++) {
      final slot = _slotOf[people[i].id];
      if (slot != null && !taken.contains(slot)) {
        result[slot] = i;
        taken.add(slot);
      }
    }
    for (var i = 0; i < people.length; i++) {
      final p = people[i];
      if (result.containsValue(i)) continue;
      final free = [
        for (var s = 0; s < count; s++)
          if (!taken.contains(s)) s,
      ];
      if (free.isEmpty) break;
      final known = free.where((s) => _lastX[s] != null).toList();
      final slot = known.isEmpty
          ? free.first
          : known.reduce(
              (a, b) =>
                  (p.x - _lastX[a]!).abs() <= (p.x - _lastX[b]!).abs() ? a : b,
            );
      _slotOf.removeWhere((_, s) => s == slot);
      _slotOf[p.id] = slot;
      result[slot] = i;
      taken.add(slot);
    }
    result.forEach((slot, i) => _lastX[slot] = people[i].x);
    return result;
  }

  void reset() {
    _slotOf.clear();
    _lastX.fillRange(0, count, null);
  }
}
