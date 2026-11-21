import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project/game/expression.dart';
import 'package:project/game/pose_scorer.dart';
import 'package:project/game/target_pose.dart';
import 'package:project/pose/body_point.dart';
import 'package:project/pose/pose_frame.dart';
import 'package:project/pose/vision_pose_service.dart';

FaceMetrics metrics({
  double mouthWidth = 0.9,
  double mouthOpen = 0.05,
  double smileCurve = 0.0,
  double leftEye = 0.3,
  double rightEye = 0.3,
  double brow = 0.35,
}) => FaceMetrics(
  mouthWidth: mouthWidth,
  mouthOpen: mouthOpen,
  smileCurve: smileCurve,
  leftEyeOpen: leftEye,
  rightEyeOpen: rightEye,
  browRaise: brow,
);

void main() {
  const scorer = ExpressionScorer();
  final neutral = metrics();

  test('a semleges arc csak a komoly arcnak felel meg', () {
    for (final e in Expression.values) {
      if (e == Expression.neutral) {
        expect(scorer.score(e, neutral), greaterThan(0.9));
      } else {
        expect(scorer.score(e, neutral), lessThan(0.2), reason: e.name);
      }
    }
  });

  test('csukott szem: mindkét szem csukva kell', () {
    expect(
      scorer.score(
        Expression.eyesClosed,
        metrics(leftEye: 0.06, rightEye: 0.07),
      ),
      greaterThan(0.9),
    );
    expect(
      scorer.score(
        Expression.eyesClosed,
        metrics(leftEye: 0.06, rightEye: 0.3),
      ),
      lessThan(0.1),
    );
  });

  test('a komoly arc nem mosoly és nem tátott száj', () {
    expect(
      scorer.score(
        Expression.neutral,
        metrics(mouthWidth: 1.12, smileCurve: 0.07),
      ),
      lessThan(0.2),
    );
    expect(
      scorer.score(Expression.neutral, metrics(mouthOpen: 0.4)),
      lessThan(0.1),
    );
  });

  test('minden kifejezést felismer a hozzá illő arcon', () {
    expect(
      scorer.score(
        Expression.smile,
        metrics(mouthWidth: 1.12, smileCurve: 0.07),
      ),
      greaterThan(0.9),
    );
    expect(
      scorer.score(Expression.surprised, metrics(mouthOpen: 0.45, brow: 0.46)),
      greaterThan(0.9),
    );
    expect(
      scorer.score(Expression.wink, metrics(leftEye: 0.08, rightEye: 0.3)),
      greaterThan(0.9),
    );
    expect(
      scorer.score(Expression.kiss, metrics(mouthWidth: 0.66)),
      greaterThan(0.9),
    );
  });

  test('a kacsintás nem ugyanaz, mint a két szem becsukása', () {
    expect(
      scorer.score(Expression.wink, metrics(leftEye: 0.06, rightEye: 0.07)),
      lessThan(0.2),
    );
  });

  test('az arckifejezés beszámít a pontba; arc nélkül kimarad', () {
    final pose = TargetPose.forCategory(PoseCategory.party, BodyMode.upper);
    final frame = _frameFrom(pose);
    const poseScorer = PoseScorer();

    final noFace = poseScorer.score(frame, pose, mirror: false)!;
    expect(noFace.expression, isNull);
    expect(noFace.accuracy, closeTo(100, 0.01));

    final smiling = poseScorer.score(
      frame,
      pose,
      mirror: false,
      face: metrics(mouthWidth: 1.12, smileCurve: 0.07),
    )!;
    expect(smiling.expression, greaterThan(0.9));
    expect(smiling.accuracy, greaterThan(98));

    final straight = poseScorer.score(
      frame,
      pose,
      mirror: false,
      face: neutral,
    )!;
    expect(straight.accuracy, lessThan(90));
  });

  test('a test mellé a hozzá legközelebbi arcot párosítja', () {
    final body = PoseFrame(
      keypoints: {
        BodyPoint.nose: const PoseKeypoint(
          point: BodyPoint.nose,
          x: 300,
          y: 200,
          z: 0,
          likelihood: 0.9,
        ),
      },
      imageWidth: 720,
      imageHeight: 1280,
      timestampMicros: 0,
    );
    FaceSample face(double x) => FaceSample(
      center: Offset(x, 205),
      size: const Size(100, 120),
      hx: 0,
      hy: 0.7,
      imageSize: const Size(720, 1280),
    );
    expect(faceForBody(body, [face(600), face(310)])!.center.dx, 310);
    expect(faceForBody(body, [face(600)]), isNull);
  });
}

/// Ugyanaz, mint a pose_scorer_test-ben: a célpózból "felismert" képkocka.
PoseFrame _frameFrom(TargetPose p) {
  const map = {
    Joint.head: BodyPoint.nose,
    Joint.lShoulder: BodyPoint.rightShoulder,
    Joint.rShoulder: BodyPoint.leftShoulder,
    Joint.lElbow: BodyPoint.rightElbow,
    Joint.rElbow: BodyPoint.leftElbow,
    Joint.lWrist: BodyPoint.rightWrist,
    Joint.rWrist: BodyPoint.leftWrist,
    Joint.lHip: BodyPoint.rightHip,
    Joint.rHip: BodyPoint.leftHip,
  };
  const scale = 400.0;
  return PoseFrame(
    keypoints: {
      for (final e in map.entries)
        if (p.has(e.key))
          e.value: PoseKeypoint(
            point: e.value,
            x: p[e.key].dx * scale,
            y: (p[e.key].dy + 0.1) * scale,
            z: 0,
            likelihood: 0.99,
          ),
    },
    imageWidth: scale,
    imageHeight: scale,
    timestampMicros: 0,
  );
}
