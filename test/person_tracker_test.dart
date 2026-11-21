import 'package:flutter_test/flutter_test.dart';
import 'package:project/pose/body_point.dart';
import 'package:project/pose/person_tracker.dart';
import 'package:project/pose/pose_frame.dart';

PoseFrame person(double cx) {
  final kps = <BodyPoint, PoseKeypoint>{};
  void put(BodyPoint p, double x, double y) =>
      kps[p] = PoseKeypoint(point: p, x: x, y: y, z: 0, likelihood: 0.9);
  put(BodyPoint.leftShoulder, cx - 20, 100);
  put(BodyPoint.rightShoulder, cx + 20, 100);
  put(BodyPoint.leftHip, cx - 15, 200);
  put(BodyPoint.rightHip, cx + 15, 200);
  return PoseFrame(
    keypoints: kps,
    imageWidth: 640,
    imageHeight: 480,
    timestampMicros: 0,
  );
}

void main() {
  test('két ember megtartja az azonosítóját, és balról jobbra jön', () {
    final tracker = PersonTracker();
    final a = tracker.update([person(450), person(150)], 0.0);
    expect(a.map((p) => p.center.dx.round()), [150, 450]);
    final leftId = a[0].id, rightId = a[1].id;

    // Kicsit mozognak, a felismerő más sorrendben adja őket.
    final b = tracker.update([person(160), person(440)], 0.05);
    expect(b[0].id, leftId);
    expect(b[1].id, rightId);
  });

  test('az eltűnt ember idővel kiesik, az új új azonosítót kap', () {
    final tracker = PersonTracker();
    final first = tracker.update([person(300)], 0.0).single.id;
    tracker.update([], 1.0);
    final second = tracker.update([person(300)], 1.05).single.id;
    expect(second, isNot(first));
  });

  test('csak a beállított számú embert követi – a legnagyobbakat', () {
    final tracker = PersonTracker();
    PoseFrame scaled(double cx, double k) {
      final f = person(cx);
      return PoseFrame(
        keypoints: {
          for (final e in f.keypoints.entries)
            e.key: PoseKeypoint(
              point: e.key,
              x: cx + (e.value.x - cx) * k,
              y: 150 + (e.value.y - 150) * k,
              z: 0,
              likelihood: 0.9,
            ),
        },
        imageWidth: 640,
        imageHeight: 480,
        timestampMicros: 0,
      );
    }

    final out = tracker.update(
      [scaled(100, 0.5), scaled(320, 1.5), scaled(540, 1.0)],
      0.0,
      maxPeople: 2,
    );
    expect(out.length, 2);
    expect(out.map((p) => p.center.dx.round()), [320, 540]);
  });
}
