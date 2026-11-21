import 'package:flutter/material.dart';

import '../ui/app_theme.dart';
import 'expression.dart';
import 'hand_shape.dart';
import 'pose_scorer.dart';
import 'target_pose.dart';

/// A célpóz pálcikaemberként. Ha [score] meg van adva, a már stimmelő
/// testrészek (végtagok, törzs, fej) zöldre váltanak.
class StickFigure extends StatelessWidget {
  const StickFigure({
    super.key,
    required this.pose,
    this.score,
    this.color = Colors.white,
  });

  final TargetPose pose;
  final PoseScore? score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(painter: _StickFigurePainter(pose, score, color)),
    );
  }
}

class _StickFigurePainter extends CustomPainter {
  _StickFigurePainter(this.pose, this.score, this.color);

  final TargetPose pose;
  final PoseScore? score;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A figura befoglaló négyzetét illesztjük a rajzfelületre, így a
    // felsőtestes póz is kitölti a kártyát.
    const headR = 0.075;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final o in pose.joints.values) {
      if (o.dx < minX) minX = o.dx;
      if (o.dx > maxX) maxX = o.dx;
      if (o.dy < minY) minY = o.dy;
      if (o.dy > maxY) maxY = o.dy;
    }
    final head = pose[Joint.head];
    if (head.dy - headR < minY) minY = head.dy - headR;
    const margin = 0.06;
    final side =
        (maxX - minX > maxY - minY ? maxX - minX : maxY - minY) + margin * 2;
    final centre = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final topLeft = centre - Offset(side / 2, side / 2);

    final box = size.shortestSide;
    final k = box / side; // figura-egység → pixel
    final origin = Offset((size.width - box) / 2, (size.height - box) / 2);
    Offset at(Joint j) => origin + (pose[j] - topLeft) * k;

    // A vonalvastagság a figura méretével arányos.
    final s = k;

    final stroke = s * 0.045;
    final paint = Paint()
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final glow = Paint()
      ..strokeWidth = stroke * 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    Color tinted(double? v) => v == null
        ? color
        : Color.lerp(color, AppColors.good, v.clamp(0.0, 1.0))!;
    Color limbColor(int i) {
      final scores = score?.limbScores;
      return tinted(scores == null || i >= scores.length ? null : scores[i]);
    }

    final torsoColor = tinted(score?.torso);
    // A fej az arckifejezéstől zöldül, a nyak a fejtartástól.
    final headColor = tinted(score?.expression);
    final neckColor = tinted(score?.head);

    void line(Offset a, Offset b, Color c) {
      glow.color = c.withValues(alpha: 0.25);
      canvas.drawLine(a, b, glow);
      paint.color = c;
      canvas.drawLine(a, b, paint);
    }

    // Törzs: vállvonal, csípővonal és a gerinc.
    final neck = (at(Joint.lShoulder) + at(Joint.rShoulder)) / 2;
    line(at(Joint.lShoulder), at(Joint.rShoulder), torsoColor);
    if (pose.has(Joint.lHip) && pose.has(Joint.rHip)) {
      final pelvis = (at(Joint.lHip) + at(Joint.rHip)) / 2;
      line(at(Joint.lHip), at(Joint.rHip), torsoColor);
      line(neck, pelvis, torsoColor);
    }

    for (var i = 0; i < kScoredLimbs.length; i++) {
      final limb = kScoredLimbs[i];
      if (!pose.has(limb.from) || !pose.has(limb.to)) continue;
      line(at(limb.from), at(limb.to), limbColor(i));
    }

    // Kéztartás a csuklókon (ha a pózban számít).
    for (final (elbow, wrist, shape, v) in [
      (Joint.lElbow, Joint.lWrist, pose.lHand, score?.lHand),
      (Joint.rElbow, Joint.rWrist, pose.rHand, score?.rHand),
    ]) {
      if (shape == HandShape.any || !pose.has(elbow) || !pose.has(wrist)) {
        continue;
      }
      _paintHand(canvas, at(elbow), at(wrist), shape, s, tinted(v), glow);
    }

    // Fej
    final headPx = at(Joint.head);
    final r = s * headR;
    // A nyak a fej alá kerül, hogy ne lógjon bele az arcba.
    line(headPx + Offset(0, r * 0.6), neck, neckColor);
    glow.color = headColor.withValues(alpha: 0.25);
    canvas.drawCircle(headPx, r, glow);
    canvas.drawCircle(headPx, r, Paint()..color = headColor);
    _paintFace(canvas, headPx, r, pose.expression);
  }

  /// Kis kéz-jel a csuklón, az alkar irányában: nyitott tenyér (legyező),
  /// ököl (gömb), mutatóujj (egy hosszú ujj), béke-jel (V).
  void _paintHand(
    Canvas canvas,
    Offset elbow,
    Offset wrist,
    HandShape shape,
    double s,
    Color color,
    Paint glow,
  ) {
    final d = wrist - elbow;
    if (d.distance < 1e-6) return;
    final angle = d.direction;
    final finger = Paint()
      ..color = color
      ..strokeWidth = s * 0.026
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    Offset ray(double da, double len) =>
        wrist + Offset.fromDirection(angle + da, len);
    void fingers(List<double> spread, double len) {
      for (final a in spread) {
        final tip = ray(a, len);
        glow.color = color.withValues(alpha: 0.25);
        canvas
          ..drawLine(wrist, tip, glow)
          ..drawLine(wrist, tip, finger);
      }
    }

    switch (shape) {
      case HandShape.open:
        fingers([-0.9, -0.45, 0, 0.45, 0.9], s * 0.065);
      case HandShape.fist:
        canvas.drawCircle(ray(0, s * 0.024), s * 0.036, Paint()..color = color);
      case HandShape.point:
        canvas.drawCircle(ray(0, s * 0.012), s * 0.018, Paint()..color = color);
        fingers([0], s * 0.085);
      case HandShape.peace:
        canvas.drawCircle(ray(0, s * 0.012), s * 0.018, Paint()..color = color);
        fingers([-0.3, 0.3], s * 0.08);
      case HandShape.any:
        break;
    }
  }

  /// Az arckifejezés a fejen: szemek és száj, sötéten.
  void _paintFace(Canvas canvas, Offset c, double r, Expression e) {
    final ink = Paint()
      ..color = const Color(0xFF2A2420)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = const Color(0xFF2A2420);
    final eyeL = c + Offset(-r * 0.36, -r * 0.18);
    final eyeR = c + Offset(r * 0.36, -r * 0.18);
    final dot = r * 0.13;

    switch (e) {
      case Expression.smile:
        canvas.drawCircle(eyeL, dot, fill);
        canvas.drawCircle(eyeR, dot, fill);
        // Széles, nyitott vigyor.
        final mouth = Path()
          ..moveTo(c.dx - r * 0.5, c.dy + r * 0.12)
          ..quadraticBezierTo(
            c.dx,
            c.dy + r * 0.85,
            c.dx + r * 0.5,
            c.dy + r * 0.12,
          )
          ..close();
        canvas.drawPath(mouth, fill);
      case Expression.surprised:
        canvas.drawCircle(eyeL, dot * 1.5, ink..strokeWidth = r * 0.12);
        canvas.drawCircle(eyeR, dot * 1.5, ink);
        // Felhúzott szemöldök és „O" száj.
        canvas.drawLine(
          eyeL + Offset(-r * 0.15, -r * 0.33),
          eyeL + Offset(r * 0.12, -r * 0.4),
          ink,
        );
        canvas.drawLine(
          eyeR + Offset(-r * 0.12, -r * 0.4),
          eyeR + Offset(r * 0.15, -r * 0.33),
          ink,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: c + Offset(0, r * 0.42),
            width: r * 0.36,
            height: r * 0.46,
          ),
          fill,
        );
      case Expression.wink:
        canvas.drawCircle(eyeL, dot, fill);
        // Csukott szem: lefelé ívelő vonal.
        canvas.drawArc(
          Rect.fromCenter(center: eyeR, width: r * 0.36, height: r * 0.26),
          3.3,
          2.8,
          false,
          ink,
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: c + Offset(0, r * 0.2),
            width: r * 0.9,
            height: r * 0.7,
          ),
          0.35,
          2.44,
          false,
          ink,
        );
      case Expression.neutral:
        canvas.drawCircle(eyeL, dot, fill);
        canvas.drawCircle(eyeR, dot, fill);
        canvas.drawLine(
          c + Offset(-r * 0.32, r * 0.42),
          c + Offset(r * 0.32, r * 0.42),
          ink,
        );
      case Expression.eyesClosed:
        // Csukott, elégedett szemek és halvány mosoly.
        for (final eye in [eyeL, eyeR]) {
          canvas.drawArc(
            Rect.fromCenter(center: eye, width: r * 0.34, height: r * 0.24),
            0.25,
            2.64,
            false,
            ink,
          );
        }
        canvas.drawArc(
          Rect.fromCenter(
            center: c + Offset(0, r * 0.3),
            width: r * 0.5,
            height: r * 0.3,
          ),
          0.4,
          2.34,
          false,
          ink,
        );
      case Expression.kiss:
        // Elégedett, csukott szemek és csücsörített száj.
        for (final eye in [eyeL, eyeR]) {
          canvas.drawArc(
            Rect.fromCenter(center: eye, width: r * 0.32, height: r * 0.24),
            3.3,
            2.8,
            false,
            ink,
          );
        }
        final lips = c + Offset(r * 0.05, r * 0.45);
        canvas.drawArc(
          Rect.fromCenter(
            center: lips + Offset(0, -r * 0.1),
            width: r * 0.26,
            height: r * 0.2,
          ),
          -1.6,
          3.2,
          false,
          ink,
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: lips + Offset(0, r * 0.1),
            width: r * 0.26,
            height: r * 0.2,
          ),
          -1.6,
          3.2,
          false,
          ink,
        );
    }
  }

  @override
  bool shouldRepaint(_StickFigurePainter old) =>
      old.pose != pose || old.score != score || old.color != color;
}
