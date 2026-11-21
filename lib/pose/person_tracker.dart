import 'dart:ui' show Offset;

import 'body_point.dart';
import 'pose_frame.dart';
import 'pose_smoother.dart';

/// Egy követett ember: stabil azonosító + a simított pontjai.
class TrackedPerson {
  const TrackedPerson(this.id, this.frame);
  final int id;
  final PoseFrame frame;

  /// A törzs közepe képpixelben (vállak + csípő átlaga).
  Offset get center => torsoCenter(frame)!;
}

/// Képkockáról képkockára párosítja a felismert embereket (a törzsközép
/// alapján a legközelebbi előzőhöz), és mindenkinek saját simítója van – így
/// a pontok nem ugrálnak, és két ember pontjai sem keverednek össze.
class PersonTracker {
  /// Ennél messzebb (képmagasság arányában) nem párosítunk – új ember.
  static const double maxJump = 0.25;

  /// Ennyi ideig (s) tartjuk meg az eltűnt embert.
  static const double forgetAfter = 0.6;

  final List<_Track> _tracks = [];
  int _nextId = 1;

  void reset() => _tracks.clear();

  _Track _newTrack(Offset center, double t) {
    final track = _Track(_nextId++, center, t);
    _tracks.add(track);
    return track;
  }

  /// [t] másodpercben. Legfeljebb [maxPeople] embert ad vissza – a
  /// legnagyobbakat (a kamerához legközelebb állókat); aki már követve van,
  /// előnyt kap, hogy a kiválasztás ne ugráljon. Balról jobbra sorban.
  List<TrackedPerson> update(
    List<PoseFrame> people,
    double t, {
    int maxPeople = 6,
  }) {
    final detections = <(PoseFrame, Offset)>[];
    for (final p in people) {
      final c = torsoCenter(p);
      if (c != null) detections.add((p, c));
    }

    // Mohó párosítás a legkisebb távolságok szerint.
    final pairs = <(double, int, int)>[];
    for (var d = 0; d < detections.length; d++) {
      final scale = detections[d].$1.imageHeight;
      for (var k = 0; k < _tracks.length; k++) {
        final dist = (detections[d].$2 - _tracks[k].center).distance / scale;
        if (dist <= maxJump) pairs.add((dist, d, k));
      }
    }
    pairs.sort((a, b) => a.$1.compareTo(b.$1));

    final trackOf = <int, _Track>{};
    final usedK = <int>{};
    for (final (_, d, k) in pairs) {
      if (trackOf.containsKey(d) || usedK.contains(k)) continue;
      trackOf[d] = _tracks[k];
      usedK.add(k);
    }

    // Kik maradnak: méret szerint, a már követettek másfélszeres súllyal.
    final order = List<int>.generate(detections.length, (i) => i)
      ..sort((a, b) {
        double rank(int d) =>
            bodySize(detections[d].$1) * (trackOf.containsKey(d) ? 1.5 : 1);
        return rank(b).compareTo(rank(a));
      });

    final out = <TrackedPerson>[];
    for (final d in order.take(maxPeople)) {
      final (raw, c) = detections[d];
      final track = trackOf[d] ?? _newTrack(c, t);
      track
        ..center = c
        ..lastSeen = t;
      out.add(TrackedPerson(track.id, track.smoother.filter(raw, t)!));
    }

    _tracks.removeWhere((tr) => t - tr.lastSeen > forgetAfter);
    out.sort((a, b) => a.center.dx.compareTo(b.center.dx));
    return out;
  }
}

class _Track {
  _Track(this.id, this.center, this.lastSeen);

  final int id;
  Offset center;
  double lastSeen;
  final PoseSmoother smoother = PoseSmoother();
}

/// A vállak és a csípő látható pontjainak átlaga; `null`, ha egyik sem
/// látszik.
Offset? torsoCenter(PoseFrame frame) {
  const torso = [
    BodyPoint.leftShoulder,
    BodyPoint.rightShoulder,
    BodyPoint.leftHip,
    BodyPoint.rightHip,
  ];
  var sum = Offset.zero;
  var n = 0;
  for (final bp in torso) {
    final k = frame[bp];
    if (k == null || k.likelihood < 0.3) continue;
    sum += Offset(k.x, k.y);
    n++;
  }
  return n == 0 ? null : sum / n.toDouble();
}

/// Mekkora az ember a képen: a látható pontjai befoglaló dobozának nagyobbik
/// oldala, képmagasság arányában.
double bodySize(PoseFrame frame) {
  double? minX, maxX, minY, maxY;
  for (final k in frame.keypoints.values) {
    if (k.likelihood < 0.3) continue;
    minX = minX == null ? k.x : (k.x < minX ? k.x : minX);
    maxX = maxX == null ? k.x : (k.x > maxX ? k.x : maxX);
    minY = minY == null ? k.y : (k.y < minY ? k.y : minY);
    maxY = maxY == null ? k.y : (k.y > maxY ? k.y : maxY);
  }
  if (minX == null) return 0;
  final w = maxX! - minX, h = maxY! - minY!;
  return (w > h ? w : h) / frame.imageHeight;
}
