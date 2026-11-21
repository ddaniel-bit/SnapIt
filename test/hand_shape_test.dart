import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project/game/hand_shape.dart';
import 'package:project/game/pose_scorer.dart';
import 'package:project/game/target_pose.dart';
import 'package:project/pose/body_point.dart';
import 'package:project/pose/pose_frame.dart';
import 'package:project/pose/vision_pose_service.dart';

// Ujjak: hüvelyk, mutató, középső, gyűrűs, kisujj.
const open = [0.9, 1.9, 2.0, 1.9, 1.8];
const fist = [0.3, 1.05, 1.0, 1.0, 1.05];
const point = [0.4, 1.9, 1.05, 1.0, 1.05];
const peace = [0.4, 1.9, 2.0, 1.05, 1.0];

void main() {
  const scorer = HandShapeScorer();

  test('minden kéztartást felismer, és a többitől megkülönbözteti', () {
    final samples = {
      HandShape.open: open,
      HandShape.fist: fist,
      HandShape.point: point,
      HandShape.peace: peace,
    };
    for (final want in samples.keys) {
      for (final entry in samples.entries) {
        final s = scorer.score(want, entry.value)!;
        if (entry.key == want) {
          expect(s, greaterThan(0.9), reason: '$want on itself');
        } else {
          expect(s, lessThan(0.8), reason: '$want on ${entry.key}');
        }
      }
    }
  });

  test('ha alig látszanak az ujjak, nem ítél', () {
    expect(scorer.score(HandShape.open, [-1, 1.9, -1, -1, -1]), isNull);
    expect(scorer.score(HandShape.any, open), isNull);
  });

  test('a kezet a megfelelő oldalhoz párosítja, és beszámít a pontba', () {
    final pose = TargetPose.forCategory(PoseCategory.party, BodyMode.upper);
    expect(pose.lHand, HandShape.open);
    final frame = _frameFrom(pose);
    HandSample hand(Joint wrist, List<double> fingers) {
      final w = pose[wrist];
      return HandSample(
        wrist: Offset(w.dx * 400, (w.dy + 0.1) * 400),
        confidence: 0.9,
        fingers: fingers,
      );
    }

    const s = PoseScorer();
    final good = s.score(
      frame,
      pose,
      mirror: false,
      hands: [hand(Joint.rWrist, open), hand(Joint.lWrist, open)],
    )!;
    expect(good.lHand, greaterThan(0.9));
    expect(good.rHand, greaterThan(0.9));
    expect(good.accuracy, greaterThan(98));

    final fists = s.score(
      frame,
      pose,
      mirror: false,
      hands: [hand(Joint.lWrist, fist), hand(Joint.rWrist, fist)],
    )!;
    expect(fists.lHand, lessThan(0.2));
    expect(fists.accuracy, lessThan(good.accuracy));

    // Ha a kezet nem látjuk, optimistán jónak vesszük.
    final unseen = s.score(frame, pose, mirror: false)!;
    expect(unseen.lHand, 1.0);
    expect(unseen.rHand, 1.0);
    expect(unseen.accuracy, closeTo(100, 0.01));
  });

  test('minden fotós póz fotója megvan az assetek között', () {
    for (final p in kPoses) {
      final photo = p.photo;
      if (photo == null) continue;
      expect(File(photo).existsSync(), isTrue, reason: photo);
    }
    expect(kPoses.where((p) => p.photo == null).map((p) => p.name), [
      'Airplane',
    ]);
  });
}

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
  return PoseFrame(
    keypoints: {
      for (final e in map.entries)
        if (p.has(e.key))
          e.value: PoseKeypoint(
            point: e.value,
            x: p[e.key].dx * 400,
            y: (p[e.key].dy + 0.1) * 400,
            z: 0,
            likelihood: 0.99,
          ),
    },
    imageWidth: 400,
    imageHeight: 400,
    timestampMicros: 0,
  );
}
