import '../pose/body_point.dart';
import '../pose/pose_frame.dart';
import '../pose/vision_pose_service.dart';

/// A pózokhoz tartozó arckifejezések.
enum Expression {
  smile('Big smile', '😁'),
  surprised('Surprised face', '😮'),
  wink('Wink', '😉'),
  kiss('Kissy face', '😗'),
  neutral('Straight face', '😐'),
  eyesClosed('Eyes closed', '😌');

  const Expression(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// Mennyire egyezik az arc a kért kifejezéssel (0–1), a Vision arcpontjaiból
/// számolt [FaceMetrics] alapján. A küszöbök tapasztalati értékek – élőben
/// finomíthatók.
class ExpressionScorer {
  const ExpressionScorer();

  // Semleges arcnál nagyjából: szájszélesség ≈ 0,9 szemtávolság, a száj
  // csukva (≈ 0,05), a szájszélek a közép magasságában.
  static const double neutralMouthWidth = 0.92;

  double score(Expression e, FaceMetrics m) => switch (e) {
    // Mosoly: szélesebb száj és/vagy felfelé húzott szájszélek.
    Expression.smile => _avg(
      _ramp(m.mouthWidth, neutralMouthWidth, neutralMouthWidth + 0.16),
      _ramp(m.smileCurve, 0.0, 0.06),
    ),
    // Meglepődés: tátott száj (a felhúzott szemöldök csak ráadás).
    Expression.surprised => _clamp(
      _ramp(m.mouthOpen, 0.12, 0.38) * 0.85 +
          _ramp(m.browRaise, 0.32, 0.45) * 0.15,
    ),
    // Kacsintás: az egyik szem sokkal csukottabb, mint a másik, ami nyitva van.
    Expression.wink => () {
      final open = m.leftEyeOpen > m.rightEyeOpen
          ? m.leftEyeOpen
          : m.rightEyeOpen;
      final shut = m.leftEyeOpen > m.rightEyeOpen
          ? m.rightEyeOpen
          : m.leftEyeOpen;
      if (open <= 0) return 0.0;
      return _ramp(1 - shut / open, 0.25, 0.55) * _ramp(open, 0.12, 0.2);
    }(),
    // Puszi / csücsörítés: keskeny, (majdnem) csukott száj.
    Expression.kiss =>
      _ramp(neutralMouthWidth - m.mouthWidth, 0.06, 0.22) *
          (1 - _ramp(m.mouthOpen, 0.2, 0.35)),
    // Komoly arc: csukott száj, se mosoly, se csücsörítés.
    Expression.neutral =>
      (1 - _ramp(m.mouthOpen, 0.1, 0.25)) *
          (1 - _ramp((m.mouthWidth - neutralMouthWidth).abs(), 0.08, 0.2)) *
          (1 - _ramp(m.smileCurve, 0.03, 0.07)),
    // Mindkét szem csukva.
    Expression.eyesClosed =>
      1 -
          _ramp(
            m.leftEyeOpen > m.rightEyeOpen ? m.leftEyeOpen : m.rightEyeOpen,
            0.1,
            0.18,
          ),
  };

  /// 0, ha [v] ≤ [from]; 1, ha [v] ≥ [to]; közte lineáris.
  static double _ramp(double v, double from, double to) =>
      _clamp((v - from) / (to - from));

  static double _avg(double a, double b) => (a + b) / 2;

  static double _clamp(double v) => v.clamp(0.0, 1.0);
}

/// A játékos teste mellé a hozzá tartozó arc: amelyik arc közepe a test
/// orrához (ha az nem látszik, a szemeihez) a legközelebb van, és elég közel.
FaceSample? faceForBody(PoseFrame body, List<FaceSample> faces) {
  if (faces.isEmpty) return null;
  PoseKeypoint? reliable(BodyPoint p) {
    final k = body[p];
    return k != null && k.likelihood >= 0.2 ? k : null;
  }

  final nose = reliable(BodyPoint.nose);
  final le = reliable(BodyPoint.leftEye), re = reliable(BodyPoint.rightEye);
  final double x, y;
  if (nose != null) {
    x = nose.x;
    y = nose.y;
  } else if (le != null && re != null) {
    x = (le.x + re.x) / 2;
    y = (le.y + re.y) / 2;
  } else {
    return null;
  }

  FaceSample? best;
  var bestDist = double.infinity;
  for (final f in faces) {
    final dx = f.center.dx - x, dy = f.center.dy - y;
    final d = dx * dx + dy * dy;
    final limit = f.size.width * 0.8;
    if (d <= limit * limit && d < bestDist) {
      best = f;
      bestDist = d;
    }
  }
  return best;
}
