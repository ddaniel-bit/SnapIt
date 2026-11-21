// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project/gaze/gaze_controller.dart';
import 'package:project/pose/pose_camera.dart';
import 'package:project/pose/vision_pose_service.dart';

class FakeTarget implements GazeTargetHandle {
  FakeTarget(this.globalRect);

  @override
  final Rect? globalRect;
  @override
  bool get isOnTopRoute => true;
  @override
  bool get enabled => true;
  @override
  final ValueNotifier<double> progress = ValueNotifier(0);

  int selected = 0;
  @override
  void onSelect() => selected++;
}

FaceSample face(double cx, double width, {double hx = 0, double hy = 0.7}) =>
    FaceSample(
      center: Offset(cx, 300),
      size: Size(width, width * 1.2),
      hx: hx,
      hy: hy,
      imageSize: const Size(720, 1280),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('az első irányítót követi, akkor is, ha nagyobb arc jön', () {
    final cam = PoseCamera();
    final gaze = GazeController(cam)
      ..screenSize = const Size(400, 800)
      ..register(FakeTarget(const Rect.fromLTWH(0, 0, 10, 10)));

    cam.faces = [face(200, 100)];
    cam.notifyListeners();
    expect(gaze.controllerFace!.center.dx, 200);

    // Egy nagyobb (közelebbi) arc jelenik meg – az irányító marad.
    cam.faces = [face(205, 100), face(550, 180)];
    cam.notifyListeners();
    expect(gaze.controllerFace!.center.dx, 205);

    // Az irányító egy pillanatra eltűnik – nem ugrik át a másikra.
    cam.faces = [face(550, 180)];
    cam.notifyListeners();
    expect(gaze.controllerFace!.center.dx, 205);

    gaze.dispose();
  });

  test('ha az irányító tartósan eltűnik, új irányítót választ', () async {
    final cam = PoseCamera();
    final gaze = GazeController(cam)
      ..screenSize = const Size(400, 800)
      ..register(FakeTarget(const Rect.fromLTWH(0, 0, 10, 10)));

    cam.faces = [face(200, 100)];
    cam.notifyListeners();
    cam.faces = [face(550, 180)];
    await Future<void>.delayed(
      GazeController.lostAfter + const Duration(milliseconds: 50),
    );
    cam.notifyListeners();
    expect(gaze.controllerFace!.center.dx, 550);

    gaze.dispose();
  });

  test(
    'kalibrálás után a középre nézés kiválasztja a középső gombot',
    () async {
      final cam = PoseCamera();
      final target = FakeTarget(const Rect.fromLTWH(150, 350, 100, 100));
      final gaze = GazeController(cam)
        ..screenSize = const Size(400, 800)
        ..register(target);

      final start = DateTime.now();
      while (target.selected == 0 &&
          DateTime.now().difference(start) < const Duration(seconds: 3)) {
        cam.faces = [face(200, 100)];
        cam.notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 33));
      }
      expect(target.selected, 1);
      // Kalibrálás (~12 képkocka) + ~1,1 mp nézés.
      expect(DateTime.now().difference(start).inMilliseconds, lessThan(2200));

      gaze.dispose();
    },
  );

  test(
    'ha a telefon átfordul, kivárja, hogy megálljon, és újrakalibrál',
    () async {
      final cam = PoseCamera();
      final gaze = GazeController(cam)
        ..screenSize = const Size(400, 800)
        ..register(FakeTarget(const Rect.fromLTWH(0, 0, 10, 10)));

      Future<void> frames(int n) async {
        for (var i = 0; i < n; i++) {
          cam.faces = [face(200, 100)];
          cam.notifyListeners();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      await frames(15);
      expect(gaze.point, isNotNull);

      // Átfordul fekvőbe.
      gaze.screenSize = const Size(800, 400);
      await frames(5);
      expect(gaze.point, isNull);
      expect(gaze.calibrating, isTrue);

      // Megáll a telefon, utána kalibrál, és újra van kurzor.
      await Future<void>.delayed(GazeController.settleAfterRotation);
      await frames(15);
      expect(gaze.point, isNotNull);
      expect(gaze.calibrating, isFalse);

      gaze.dispose();
    },
  );
}
