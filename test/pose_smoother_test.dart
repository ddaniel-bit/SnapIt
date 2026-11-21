import 'package:flutter_test/flutter_test.dart';
import 'package:project/pose/body_point.dart';
import 'package:project/pose/pose_frame.dart';
import 'package:project/pose/pose_smoother.dart';

PoseFrame frame(Map<BodyPoint, (double, double)> pts) => PoseFrame(
  keypoints: {
    for (final e in pts.entries)
      e.key: PoseKeypoint(
        point: e.key,
        x: e.value.$1,
        y: e.value.$2,
        z: 0,
        likelihood: 0.9,
      ),
  },
  imageWidth: 480,
  imageHeight: 480,
  timestampMicros: 0,
);

void main() {
  const wrist = BodyPoint.leftWrist;

  test('egyetlen elugró képkocka nem rántja el a pontot', () {
    final s = PoseSmoother();
    s.filter(frame({wrist: (100, 100)}), 0.0);
    s.filter(frame({wrist: (100, 100)}), 0.066);
    final spiked = s.filter(frame({wrist: (300, 300)}), 0.133)!;
    expect(spiked[wrist]!.x, closeTo(100, 1));
    final back = s.filter(frame({wrist: (100, 100)}), 0.2)!;
    expect(back[wrist]!.x, closeTo(100, 1));
  });

  test('a megerősített nagy mozdulatot követi', () {
    final s = PoseSmoother();
    s.filter(frame({wrist: (100, 100)}), 0.0);
    s.filter(frame({wrist: (300, 300)}), 0.066);
    final moved = s.filter(frame({wrist: (300, 300)}), 0.133)!;
    expect(moved[wrist]!.x, greaterThan(150));
  });

  test('a rövid ideig hiányzó pont a helyén marad, aztán eltűnik', () {
    final s = PoseSmoother();
    const nose = BodyPoint.nose;
    s.filter(frame({wrist: (100, 100), nose: (200, 50)}), 0.0);
    final held = s.filter(frame({nose: (200, 50)}), 0.1)!;
    expect(held[wrist]!.x, closeTo(100, 0.01));
    final gone = s.filter(frame({nose: (200, 50)}), 0.6)!;
    expect(gone[wrist], isNull);
  });
}
