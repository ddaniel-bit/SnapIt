import 'dart:math' as math;

import 'body_point.dart';
import 'pose_frame.dart';

/// A pose-pontok remegésének csillapítása One Euro szűrővel (Casiez et al.,
/// 2012).
///
/// Lényege: adaptív aluláteresztő szűrő. Ha a pont lassan mozog (vagy áll),
/// a vágási frekvencia alacsony → erősen simít, nem vibrál; ha gyorsan mozog,
/// a vágási frekvencia nő → alig simít, így a csontváz nem késik a mozdulat
/// mögött.
///
/// A koordinátákat a kép magasságára normalizálva szűrjük, így a paraméterek
/// nem függnek a kamera felbontásától. A bizonytalan pontokat (alacsony
/// likelihood) erősebben fogjuk vissza: egy-egy hibás észlelés nem rántja el
/// a csontvázat.
///
/// Bal–jobb csere elleni védelem: oldalnézetben a modell egy-egy képkockára
/// felcserélheti a két lábat / kart. Ha a felcserélt hozzárendelés sokkal
/// jobban illik az előző (simított) helyzethez, visszacseréljük – különben a
/// simítás a két végtagot "összeátlagolná" (keresztbe álló, tükrözöttnek
/// látszó lábak). Ha a csere tartósan megmarad (pl. tényleg megfordult),
/// elfogadjuk.
class PoseSmoother {
  PoseSmoother({
    this.minCutoff = 0.6,
    this.beta = 3.0,
    this.derivativeCutoff = 1.0,
    this.resetAfter = 0.6,
  });

  /// Nyugalmi vágási frekvencia (Hz): kisebb = simább, de lassabb.
  final double minCutoff;

  /// Mennyire nő a vágási frekvencia a sebességgel (kép-magasság / s-ban).
  final double beta;

  /// A sebességbecslés simítása (Hz).
  final double derivativeCutoff;

  /// Ha ennyi ideig (s) nincs ember a képen, újrakezdjük (nem húzzuk a régi
  /// helyzetből az újat).
  final double resetAfter;

  final Map<BodyPoint, _PointFilter> _filters = {};
  double? _lastT;

  /// Ha egy pont egy-egy képkockára eltűnik (vagy nagyon bizonytalan), ennyi
  /// ideig (s) a helyén tartjuk – így nem villog a csontváz.
  static const double holdFor = 0.4;

  /// Ennél bizonytalanabb pontot nem engedünk a szűrőbe.
  static const double dropBelow = 0.15;

  /// Végtag-csoportonként: hány egymás utáni képkockán láttunk cserét.
  final List<int> _swapStreak = List<int>.filled(_limbs.length, 0);

  /// Ennyi egymás utáni képkockányi csere után elfogadjuk az új oldalakat.
  static const int acceptSwapAfter = 5;

  /// A felcserélt hozzárendelésnek ennyivel kell jobbnak lennie.
  static const double swapCostRatio = 0.5;

  /// Ennél kisebb eltérésnél (képmagasság arányában) nem vizsgáljuk.
  static const double swapMinCost = 0.03;

  /// A bal / jobb végtag-csoportok (a vállat és a csípőt nem cseréljük).
  static const List<(List<BodyPoint>, List<BodyPoint>)> _limbs = [
    (
      [
        BodyPoint.leftKnee,
        BodyPoint.leftAnkle,
        BodyPoint.leftHeel,
        BodyPoint.leftFootIndex,
      ],
      [
        BodyPoint.rightKnee,
        BodyPoint.rightAnkle,
        BodyPoint.rightHeel,
        BodyPoint.rightFootIndex,
      ],
    ),
    (
      [
        BodyPoint.leftElbow,
        BodyPoint.leftWrist,
        BodyPoint.leftPinky,
        BodyPoint.leftIndex,
        BodyPoint.leftThumb,
      ],
      [
        BodyPoint.rightElbow,
        BodyPoint.rightWrist,
        BodyPoint.rightPinky,
        BodyPoint.rightIndex,
        BodyPoint.rightThumb,
      ],
    ),
  ];

  void reset() {
    _filters.clear();
    _lastT = null;
    _swapStreak.fillRange(0, _swapStreak.length, 0);
  }

  /// A bejövő pontok bal / jobb végtagjainak visszacserélése, ha a felcserélt
  /// hozzárendelés sokkal jobban illik az előző simított helyzethez.
  Map<BodyPoint, PoseKeypoint> _unswap(
    Map<BodyPoint, PoseKeypoint> input,
    double scale,
  ) {
    var result = input;
    for (var g = 0; g < _limbs.length; g++) {
      final (left, right) = _limbs[g];
      var direct = 0.0, swapped = 0.0, pairs = 0;
      for (var i = 0; i < left.length; i++) {
        final l = input[left[i]], r = input[right[i]];
        final pl = _filters[left[i]], pr = _filters[right[i]];
        if (l == null || r == null || pl?._x == null || pr?._x == null) {
          continue;
        }
        double d(PoseKeypoint k, _PointFilter f) {
          final dx = k.x / scale - f._x!, dy = k.y / scale - f._y!;
          return dx * dx + dy * dy;
        }

        direct += d(l, pl!) + d(r, pr!);
        swapped += d(l, pr) + d(r, pl);
        pairs++;
      }
      if (pairs == 0) continue;
      final looksSwapped =
          direct > swapMinCost * swapMinCost * pairs &&
          swapped < direct * swapCostRatio;
      if (!looksSwapped) {
        _swapStreak[g] = 0;
        continue;
      }
      _swapStreak[g]++;
      if (_swapStreak[g] >= acceptSwapAfter) {
        // Tartós: valódi oldalváltás – elfogadjuk, a szűrők újraindulnak.
        for (final p in [...left, ...right]) {
          _filters.remove(p);
        }
        _swapStreak[g] = 0;
        continue;
      }
      if (identical(result, input)) result = Map.of(input);
      for (var i = 0; i < left.length; i++) {
        final l = input[left[i]], r = input[right[i]];
        if (l == null || r == null) continue;
        result[left[i]] = _relabel(r, left[i]);
        result[right[i]] = _relabel(l, right[i]);
      }
    }
    return result;
  }

  static PoseKeypoint _relabel(PoseKeypoint k, BodyPoint point) => PoseKeypoint(
    point: point,
    x: k.x,
    y: k.y,
    z: k.z,
    likelihood: k.likelihood,
  );

  /// A simított képkocka. [t] másodpercben. `null` bemenetre `null`.
  PoseFrame? filter(PoseFrame? frame, double t) {
    if (frame == null || frame.isEmpty) {
      if (_lastT != null && t - _lastT! > resetAfter) reset();
      return frame;
    }
    final last = _lastT;
    if (last != null && (t - last > resetAfter || t <= last)) reset();
    final dt = _lastT == null ? null : t - _lastT!;
    _lastT = t;

    final scale = frame.imageHeight > 0 ? frame.imageHeight : 1.0;
    final input = _unswap(frame.keypoints, scale);
    final keypoints = <BodyPoint, PoseKeypoint>{};
    for (final entry in input.entries) {
      final kp = entry.value;
      if (kp.likelihood < dropBelow) continue;
      final f = _filters.putIfAbsent(entry.key, _PointFilter.new);
      final (x, y) = f.update(
        kp.x / scale,
        kp.y / scale,
        dt,
        kp.likelihood,
        minCutoff,
        beta,
        derivativeCutoff,
      );
      f
        ..lastSeen = t
        ..likelihood = f.likelihood == null
            ? kp.likelihood
            : f.likelihood! * 0.6 + kp.likelihood * 0.4;
      keypoints[entry.key] = PoseKeypoint(
        point: kp.point,
        x: x * scale,
        y: y * scale,
        z: kp.z,
        // A megbízhatóságot is simítjuk: ne villogjon a küszöb körül.
        likelihood: f.likelihood!,
      );
    }

    // Az épp hiányzó pontok rövid ideig a helyükön maradnak.
    for (final entry in _filters.entries) {
      final f = entry.value;
      if (keypoints.containsKey(entry.key) || f._x == null) continue;
      final age = t - f.lastSeen;
      if (age > holdFor) continue;
      keypoints[entry.key] = PoseKeypoint(
        point: entry.key,
        x: f._x! * scale,
        y: f._y! * scale,
        z: 0,
        likelihood: (f.likelihood ?? 0.5) * (1 - age / holdFor * 0.5),
      );
    }
    return PoseFrame(
      keypoints: keypoints,
      imageWidth: frame.imageWidth,
      imageHeight: frame.imageHeight,
      timestampMicros: frame.timestampMicros,
    );
  }
}

/// Egy pont két koordinátájának szűrője (közös sebességgel, hogy a két
/// tengely ugyanúgy reagáljon a mozgásra).
class _PointFilter {
  double? _x;
  double? _y;
  double _dx = 0;
  double _dy = 0;

  /// Mikor (s) láttuk utoljára, és a simított megbízhatósága.
  double lastSeen = 0;
  double? likelihood;

  /// Egy nagy ugrás jelöltje: csak akkor fogadjuk el, ha a következő
  /// képkocka is megerősíti (egyetlen elugró képkocka nem rántja el a pontot).
  double? _pendingX;
  double? _pendingY;

  /// Ekkora ugrás (képmagasság arányában) egy képkocka alatt gyanús…
  static const double spikeJump = 0.12;

  /// …és ennyin belül kell lennie a következőnek, hogy elfogadjuk.
  static const double confirmWithin = 0.06;

  (double, double) update(
    double x,
    double y,
    double? dt,
    double likelihood,
    double minCutoff,
    double beta,
    double derivativeCutoff,
  ) {
    final px = _x;
    final py = _y;
    if (px == null || py == null || dt == null || dt <= 0) {
      _x = x;
      _y = y;
      _dx = 0;
      _dy = 0;
      return (x, y);
    }

    // Elugró képkocka kiszűrése.
    final jump = math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
    if (jump > spikeJump) {
      final cx = _pendingX, cy = _pendingY;
      final confirmed =
          cx != null &&
          cy != null &&
          math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) < confirmWithin;
      if (!confirmed) {
        _pendingX = x;
        _pendingY = y;
        return (px, py);
      }
    }
    _pendingX = null;
    _pendingY = null;

    // Sebesség (simítva).
    final ad = _alpha(derivativeCutoff, dt);
    _dx = ad * ((x - px) / dt) + (1 - ad) * _dx;
    _dy = ad * ((y - py) / dt) + (1 - ad) * _dy;
    final speed = math.sqrt(_dx * _dx + _dy * _dy);

    // Adaptív vágási frekvencia → simítási együttható.
    var a = _alpha(minCutoff + beta * speed, dt);

    // Bizonytalan pont: lassabban engedjük el a régi helyzetet.
    if (likelihood < 0.5) a *= 0.35 + 0.65 * likelihood.clamp(0.0, 1.0);

    _x = a * x + (1 - a) * px;
    _y = a * y + (1 - a) * py;
    return (_x!, _y!);
  }

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }
}
