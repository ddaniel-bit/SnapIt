import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../pose/body_point.dart';
import '../pose/pose_frame.dart';
import '../pose/pose_geometry.dart' show kMinLikelihood;
import '../pose/vision_pose_service.dart' show FaceMetrics, HandSample;
import 'expression.dart';
import 'hand_shape.dart';
import 'target_pose.dart';

/// Egy képkocka értékelése a célpózhoz képest.
class PoseScore {
  const PoseScore(
    this.accuracy,
    this.limbScores, {
    required this.torso,
    required this.head,
    this.expression,
    this.lHand,
    this.rHand,
  });

  /// 0–100.
  final double accuracy;

  /// Szakaszonként 0–1 (a [kScoredLimbs] sorrendjében) – a pálcikaember ezzel
  /// színezi, melyik végtag stimmel már.
  final List<double> limbScores;

  /// A törzs (csípő→váll, vagy ha a csípő nem látszik, a vállvonal) és a fej
  /// (nyak→orr) egyezése, 0–1.
  final double torso;
  final double head;

  /// Az arckifejezés egyezése (0–1), vagy `null`, ha az arcot nem láttuk
  /// (pl. túl messze áll) – ilyenkor nem számít bele.
  final double? expression;

  /// A kép bal / jobb oldali kezének ujjtartása (0–1), vagy `null`, ha a
  /// pózban nem számít, vagy a kezet nem láttuk jól.
  final double? lHand;
  final double? rHand;
}

/// A felismert testet a célpózhoz méri: minden végtagszakasz IRÁNYÁT veti össze
/// a pálcikaember megfelelő szakaszáéval. A testmérettől, a kamerától való
/// távolságtól és a képen elfoglalt helytől így független.
/// Ennél bizonytalanabb kéz ujjtartását nem ítéljük meg (jónak vesszük).
const double kMinHandConfidence = 0.5;

class PoseScorer {
  const PoseScorer();

  /// Ennyi fokos eltérésig teljes pont jár egy szakaszra…
  static const double perfectWithinDeg = 12;

  /// …és ennyitől már nulla.
  static const double zeroAtDeg = 75;

  /// `null`, ha a játékos nem látszik eléggé: a vállak mindig kellenek,
  /// teljes testes póznál a csípő is. Felsőtestes póznál a lábak nem
  /// számítanak, és ha a csípő nem látszik, a törzs helyett a vállvonalat
  /// vetjük össze.
  ///
  /// Ha egy testrész azért hiányzik, mert kilóg a képből (pl. a felnyújtott
  /// kéz a kép tetején), optimistán a helyén lévőnek vesszük – lásd
  /// [_inferOffImage].
  PoseScore? score(
    PoseFrame? frame,
    TargetPose target, {
    required bool mirror,
    FaceMetrics? face,
    List<HandSample> hands = const [],
  }) {
    if (frame == null || frame.isEmpty) return null;

    final pts = _toScreenJoints(frame, mirror, requireHips: false);
    if (pts == null) return null;
    final inferred = _inferOffImage(pts, target, frame);
    if (target.mode == BodyMode.full &&
        (pts[Joint.lHip] == null || pts[Joint.rHip] == null)) {
      return null;
    }

    final limbScores = <double>[];
    var sum = 0.0, weights = 0.0;
    for (final limb in kScoredLimbs) {
      if (!target.has(limb.from) || !target.has(limb.to)) {
        limbScores.add(0); // ebben a pózban nem számít (és nincs is rajzolva)
        continue;
      }
      final a = pts[limb.from], b = pts[limb.to];
      final s = (a == null || b == null)
          ? 0.0
          : _match(b - a, target[limb.to] - target[limb.from]);
      limbScores.add(s);
      sum += s * limb.weight;
      weights += limb.weight;
    }

    final ls = pts[Joint.lShoulder]!, rs = pts[Joint.rShoulder]!;
    final lh = pts[Joint.lHip], rh = pts[Joint.rHip];
    final double torsoScore;
    if (lh != null && rh != null) {
      // Törzs: csípőközéptől vállközépig.
      torsoScore = _match(
        _mid(ls, rs) - _mid(lh, rh),
        _mid(target[Joint.lShoulder], target[Joint.rShoulder]) -
            _mid(target[Joint.lHip], target[Joint.rHip]),
      );
    } else {
      torsoScore = _match(
        rs - ls,
        target[Joint.rShoulder] - target[Joint.lShoulder],
      );
    }
    sum += torsoScore * kTorsoWeight;
    weights += kTorsoWeight;

    // Fej: a vállközéptől az orr felé mutató irány (billentés, lehajtás).
    final nose = pts[Joint.head];
    final headScore = nose == null
        ? 0.0
        : _match(
            nose - _mid(ls, rs),
            target[Joint.head] -
                _mid(target[Joint.lShoulder], target[Joint.rShoulder]),
          );
    sum += headScore * kHeadWeight;
    weights += kHeadWeight;

    // Arckifejezés – csak ha az arcot is látjuk.
    final expressionScore = face == null
        ? null
        : const ExpressionScorer().score(target.expression, face);
    if (expressionScore != null) {
      sum += expressionScore * kExpressionWeight;
      weights += kExpressionWeight;
    }

    // Ujjtartás – kezenként, ha a pózban számít és a kezet látjuk.
    final (lHand, rHand) = _scoreHands(
      pts,
      inferred,
      target,
      hands,
      frame,
      mirror: mirror,
    );
    for (final h in [lHand, rHand]) {
      if (h == null) continue;
      sum += h * kHandWeight;
      weights += kHandWeight;
    }

    return PoseScore(
      100 * sum / weights,
      limbScores,
      torso: torsoScore,
      head: headScore,
      expression: expressionScore,
      lHand: lHand,
      rHand: rHand,
    );
  }

  /// Ennyire közel a kép széléhez már „kilógónak" számít egy pont (a kép
  /// méretének arányában) – a szélen a felismerő amúgy is gyakran elveszti.
  static const double edgeMargin = 0.03;

  /// A hiányzó, de a képből valószínűleg kilógó testrészek kikövetkeztetése.
  ///
  /// A szülő ízületből (pl. könyök → csukló) a célpóz irányába, a játékos
  /// testméretéhez arányos hosszon megbecsüljük, hol volna a pont. Ha ez a
  /// becslés a képen kívülre (vagy a széléhez) esik, a pont csak azért nem
  /// látszik, mert nem fért bele a képbe: optimistán a helyén lévőnek vesszük.
  /// Ha a becslés a képen belül van, nem találgatunk – ott látnunk kellene.
  /// Láncban is működik: ha a könyök kilóg, a csukló is a könyökből becsülhető.
  Set<Joint> _inferOffImage(
    Map<Joint, Offset> pts,
    TargetPose target,
    PoseFrame frame,
  ) {
    final inferred = <Joint>{};
    final ls = pts[Joint.lShoulder]!, rs = pts[Joint.rShoulder]!;
    final tls = target[Joint.lShoulder], trs = target[Joint.rShoulder];

    // Testméret: célpóz-egység → képpixel (vállszélesség, ill. ha az oldalra
    // fordulás miatt az kicsi, törzshossz alapján).
    var scale = (rs - ls).distance / (trs - tls).distance;
    final lh = pts[Joint.lHip], rh = pts[Joint.rHip];
    if (lh != null && rh != null) {
      final torso = (_mid(ls, rs) - _mid(lh, rh)).distance;
      final targetTorso =
          (_mid(tls, trs) - _mid(target[Joint.lHip], target[Joint.rHip]))
              .distance;
      scale = math.max(scale, torso / targetTorso);
    }
    if (!scale.isFinite || scale <= 0) return inferred;

    final w = frame.imageWidth, h = frame.imageHeight;
    bool offImage(Offset p) =>
        p.dx < w * edgeMargin ||
        p.dx > w * (1 - edgeMargin) ||
        p.dy < h * edgeMargin ||
        p.dy > h * (1 - edgeMargin);

    void infer(Offset? from, Joint fromJoint, Joint to) {
      if (from == null || pts[to] != null) return;
      if (!target.has(fromJoint) || !target.has(to)) return;
      final guess = from + (target[to] - target[fromJoint]) * scale;
      if (offImage(guess)) {
        pts[to] = guess;
        inferred.add(to);
      }
    }

    // Csípő a vállból (ha túl közel áll, és lent kilóg).
    infer(ls, Joint.lShoulder, Joint.lHip);
    infer(rs, Joint.rShoulder, Joint.rHip);

    // Fej a vállközépből (ha fent kilóg).
    if (pts[Joint.head] == null) {
      final guess =
          _mid(ls, rs) + (target[Joint.head] - _mid(tls, trs)) * scale;
      if (offImage(guess)) {
        pts[Joint.head] = guess;
        inferred.add(Joint.head);
      }
    }

    // Végtagok a törzstől kifelé (a lista sorrendje: váll→könyök→csukló,
    // csípő→térd→boka), így a lánc is kikövetkeztethető.
    for (final limb in kScoredLimbs) {
      infer(pts[limb.from], limb.from, limb.to);
    }
    return inferred;
  }

  /// A két kéz ujjtartása. A felismert kezet a csuklója alapján párosítjuk a
  /// test megfelelő oldalához; egy kéz csak egy oldalhoz tartozhat. Ha egy
  /// kezet nem látunk, optimistán jónak vesszük.
  (double?, double?) _scoreHands(
    Map<Joint, Offset> pts,
    Set<Joint> inferred,
    TargetPose target,
    List<HandSample> hands,
    PoseFrame frame, {
    required bool mirror,
  }) {
    final shoulderW = (pts[Joint.rShoulder]! - pts[Joint.lShoulder]!).distance;
    final limit = math.max(shoulderW * 0.8, frame.imageHeight * 0.05);
    final screenHands = [
      for (final h in hands)
        (
          h,
          Offset(
            mirror ? frame.imageWidth - h.wrist.dx : h.wrist.dx,
            h.wrist.dy,
          ),
        ),
    ];

    HandSample? nearest(Joint wrist, HandSample? taken) {
      final w = pts[wrist];
      // A kikövetkeztetett (képen kívüli) csukló kezét nem látjuk.
      if (w == null || inferred.contains(wrist)) return null;
      HandSample? best;
      var bestD = limit;
      for (final (h, p) in screenHands) {
        if (identical(h, taken)) continue;
        final d = (p - w).distance;
        if (d < bestD) {
          best = h;
          bestD = d;
        }
      }
      return best;
    }

    // Ha a kezet nem látjuk (kilóg a képből, takarásban van, vagy túl kicsi
    // ahhoz, hogy az ujjak kivehetők legyenek), optimistán jónak vesszük –
    // ugyanúgy, mint a képből kilógó végtagokat.
    const scorer = HandShapeScorer();
    double? judge(HandShape shape, HandSample? hand) {
      if (shape == HandShape.any) return null;
      // Nem látjuk megbízhatóan → jónak vesszük.
      if (hand == null || hand.confidence < kMinHandConfidence) return 1.0;
      return scorer.score(shape, hand.fingers) ?? 1.0;
    }

    final lh = target.lHand == HandShape.any
        ? null
        : nearest(Joint.lWrist, null);
    final rh = target.rHand == HandShape.any ? null : nearest(Joint.rWrist, lh);
    return (judge(target.lHand, lh), judge(target.rHand, rh));
  }

  double _match(Offset got, Offset want) {
    if (got.distance < 1e-6 || want.distance < 1e-6) return 0;
    var d = (got.direction - want.direction).abs() * 180 / math.pi;
    if (d > 180) d = 360 - d;
    return (1 - (d - perfectWithinDeg) / (zeroAtDeg - perfectWithinDeg)).clamp(
      0.0,
      1.0,
    );
  }

  static Offset _mid(Offset a, Offset b) => (a + b) / 2;

  /// A testpontok képernyő-koordinátában, képernyő-oldal szerinti
  /// ízületnevekkel. A nem megbízható pontok kimaradnak.
  Map<Joint, Offset>? _toScreenJoints(
    PoseFrame frame,
    bool mirror, {
    required bool requireHips,
  }) {
    Offset? p(BodyPoint bp) {
      final k = frame[bp];
      if (k == null || !k.isReliable(kMinLikelihood)) return null;
      return Offset(mirror ? frame.imageWidth - k.x : k.x, k.y);
    }

    final ls = p(BodyPoint.leftShoulder), rs = p(BodyPoint.rightShoulder);
    final lh = p(BodyPoint.leftHip), rh = p(BodyPoint.rightHip);
    if (ls == null || rs == null) return null;
    if (requireHips && (lh == null || rh == null)) return null;

    // Melyik testfél látszik a képernyő bal oldalán?
    final bodyLeftOnScreenLeft = ls.dx < rs.dx;
    BodyPoint side(BodyPoint left, BodyPoint right, bool screenLeft) =>
        (screenLeft == bodyLeftOnScreenLeft) ? left : right;

    final out = <Joint, Offset>{};
    final nose = p(BodyPoint.nose);
    if (nose != null) out[Joint.head] = nose;
    void put(Joint j, BodyPoint left, BodyPoint right, bool screenLeft) {
      final v = p(side(left, right, screenLeft));
      if (v != null) out[j] = v;
    }

    put(Joint.lShoulder, BodyPoint.leftShoulder, BodyPoint.rightShoulder, true);
    put(
      Joint.rShoulder,
      BodyPoint.leftShoulder,
      BodyPoint.rightShoulder,
      false,
    );
    put(Joint.lElbow, BodyPoint.leftElbow, BodyPoint.rightElbow, true);
    put(Joint.rElbow, BodyPoint.leftElbow, BodyPoint.rightElbow, false);
    put(Joint.lWrist, BodyPoint.leftWrist, BodyPoint.rightWrist, true);
    put(Joint.rWrist, BodyPoint.leftWrist, BodyPoint.rightWrist, false);
    put(Joint.lHip, BodyPoint.leftHip, BodyPoint.rightHip, true);
    put(Joint.rHip, BodyPoint.leftHip, BodyPoint.rightHip, false);
    put(Joint.lKnee, BodyPoint.leftKnee, BodyPoint.rightKnee, true);
    put(Joint.rKnee, BodyPoint.leftKnee, BodyPoint.rightKnee, false);
    put(Joint.lAnkle, BodyPoint.leftAnkle, BodyPoint.rightAnkle, true);
    put(Joint.rAnkle, BodyPoint.leftAnkle, BodyPoint.rightAnkle, false);
    return out;
  }
}
