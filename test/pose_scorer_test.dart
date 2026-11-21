import 'package:flutter_test/flutter_test.dart';
import 'package:project/game/pose_scorer.dart';
import 'package:project/game/target_pose.dart';
import 'package:project/pose/body_point.dart';
import 'package:project/pose/pose_frame.dart';

/// A célpózból épít egy "felismert" képkockát (képernyő-bal = a test jobbja,
/// ahogy egy tükrözött előlapi kamerán látszik).
PoseFrame frameFrom(
  TargetPose p, {
  double scale = 400,
  bool flip = false,
  double shiftY = 0,
}) {
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
    Joint.lKnee: BodyPoint.rightKnee,
    Joint.rKnee: BodyPoint.leftKnee,
    Joint.lAnkle: BodyPoint.rightAnkle,
    Joint.rAnkle: BodyPoint.leftAnkle,
  };
  final kps = <BodyPoint, PoseKeypoint>{};
  map.forEach((j, bp) {
    if (!p.has(j)) return;
    final o = p[j];
    final x = flip ? 1 - o.dx : o.dx;
    kps[bp] = PoseKeypoint(
      point: bp,
      x: x * scale,
      y: (o.dy + shiftY) * scale,
      z: 0,
      likelihood: 0.99,
    );
  });
  return PoseFrame(
    keypoints: kps,
    imageWidth: scale,
    imageHeight: scale,
    timestampMicros: 0,
  );
}

void main() {
  const scorer = PoseScorer();

  test('a célpóz pontos utánzása 100%', () {
    for (final p in kPoses) {
      final s = scorer.score(frameFrom(p), p, mirror: false)!;
      expect(s.accuracy, closeTo(100, 0.01), reason: p.name);
    }
  });

  test('más póz alacsonyabb pontot kap', () {
    final heart = TargetPose.forCategory(PoseCategory.couple, BodyMode.full);
    final star = TargetPose.forCategory(PoseCategory.family, BodyMode.full);
    final s = scorer.score(frameFrom(star), heart, mirror: false)!;
    expect(s.accuracy, lessThan(75));
  });

  test('aszimmetrikus póz tükörképe nem ér teljes pontot', () {
    final disco = TargetPose.forCategory(PoseCategory.couple, BodyMode.upper);
    final s = scorer.score(frameFrom(disco, flip: true), disco, mirror: false)!;
    expect(s.accuracy, lessThan(70));
  });

  test('felsőtestes póz: csípő és láb nélkül is 100%', () {
    final flex = TargetPose.forCategory(PoseCategory.family, BodyMode.upper);
    final f = frameFrom(flex);
    final noHips = PoseFrame(
      keypoints: Map.of(f.keypoints)
        ..remove(BodyPoint.leftHip)
        ..remove(BodyPoint.rightHip),
      imageWidth: f.imageWidth,
      imageHeight: f.imageHeight,
      timestampMicros: 0,
    );
    expect(
      scorer.score(noHips, flex, mirror: false)!.accuracy,
      closeTo(100, 0.01),
    );
  });

  test('teljes testes pózon a hiányzó lábak pontot vesznek el', () {
    final star = TargetPose.forCategory(PoseCategory.family, BodyMode.full);
    final upper = TargetPose.forCategory(PoseCategory.family, BodyMode.upper);
    // felsőtestes képkocka (nincs láb) a teljes testes pózra: a lábak 0-t kapnak
    final s = scorer.score(frameFrom(upper), star, mirror: false)!;
    expect(s.accuracy, lessThan(80));
  });

  test('minden kategóriában van felsőtestes és teljes testes póz', () {
    for (final c in PoseCategory.values) {
      for (final m in BodyMode.values) {
        expect(TargetPose.forCategory(c, m).mode, m);
      }
    }
  });

  PoseFrame without(PoseFrame f, Set<BodyPoint> drop) => PoseFrame(
    keypoints: Map.of(f.keypoints)..removeWhere((k, _) => drop.contains(k)),
    imageWidth: f.imageWidth,
    imageHeight: f.imageHeight,
    timestampMicros: 0,
  );

  test('a képből kilógó kezeket optimistán a helyükön lévőnek veszi', () {
    final ymca = TargetPose.forCategory(PoseCategory.party, BodyMode.upper);
    // Lejjebb csúsztatva a csuklók a kép teteje fölé kerülnek – a felismerő
    // ezeket nem látja.
    final f = without(frameFrom(ymca, shiftY: -0.05), {
      BodyPoint.leftWrist,
      BodyPoint.rightWrist,
    });
    expect(scorer.score(f, ymca, mirror: false)!.accuracy, closeTo(100, 0.01));
  });

  test('a képen belül hiányzó kezet nem találgatja ki', () {
    final ymca = TargetPose.forCategory(PoseCategory.party, BodyMode.upper);
    final f = without(frameFrom(ymca, shiftY: 0.1), {
      BodyPoint.leftWrist,
      BodyPoint.rightWrist,
    });
    expect(scorer.score(f, ymca, mirror: false)!.accuracy, lessThan(80));
  });

  test('teljes testes póz: a kép aljából kilógó lábakat is kikövetkezteti', () {
    final sumo = TargetPose.forCategory(PoseCategory.family, BodyMode.full);
    final f = without(frameFrom(sumo, shiftY: 0.2), {
      BodyPoint.leftAnkle,
      BodyPoint.rightAnkle,
    });
    expect(scorer.score(f, sumo, mirror: false)!.accuracy, closeTo(100, 0.01));
  });

  test('kategóriánként és módonként több póz van, a véletlen nem ismétel', () {
    for (final c in PoseCategory.values) {
      for (final m in BodyMode.values) {
        final all = TargetPose.all(c, m);
        expect(all.length, greaterThanOrEqualTo(2));
        for (final p in all) {
          expect(TargetPose.random(c, m, except: p), isNot(p));
        }
      }
    }
  });

  test('párban mindenki más pózt kap, amíg van eltérő', () {
    for (final c in PoseCategory.values) {
      for (final m in BodyMode.values) {
        final pair = TargetPose.forPlayers(c, m, 2);
        expect(pair[0], isNot(pair[1]));
        expect(pair.every((p) => p.category == c && p.mode == m), isTrue);
        // Többen, mint ahány póz van: ismétlődik, de mindenki kap egyet.
        expect(TargetPose.forPlayers(c, m, 5).length, 5);
        // Az előző kör első póza nem kezd újra.
        final again = TargetPose.forPlayers(c, m, 1, except: pair[0]);
        expect(again.first, isNot(pair[0]));
      }
    }
  });

  test('nincs törzs → null', () {
    expect(
      scorer.score(
        const PoseFrame(
          keypoints: {},
          imageWidth: 1,
          imageHeight: 1,
          timestampMicros: 0,
        ),
        kPoses.first,
        mirror: false,
      ),
      isNull,
    );
  });
}
