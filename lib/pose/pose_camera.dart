import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import 'person_tracker.dart';
import 'skeleton_painter.dart';
import 'vision_pose_service.dart';

/// Az egész appban egyetlen kamera + póz-felismerő fut; a képernyők ezt
/// figyelik ([PoseCameraScope.of]). Így oldalváltáskor nem kell újranyitni a
/// kamerát.
class PoseCamera extends ChangeNotifier {
  final VisionPoseService _detector = VisionPoseService();
  final PersonTracker _tracker = PersonTracker();

  CameraController? controller;
  CameraDescription? camera;
  String? error;

  /// A képen lévő emberek simított pontjai, balról jobbra.
  List<TrackedPerson> people = const [];

  /// Legfeljebb ennyi embert követünk (a beállított játékosszám).
  int maxPeople = 1;

  /// Kellenek-e az arcok – csak akkor kérjük a Visiontől, ha valaki
  /// használja: a nézéses navigáció vagy a játék (arckifejezés).
  bool gazeWantsFace = false;
  bool gameWantsFace = false;
  bool get wantFace => gazeWantsFace || gameWantsFace;

  /// Kellenek-e a kezek (ujjtartás a játék alatt).
  bool gameWantsHands = false;

  /// A kezek a legutóbbi képkockán (ha [gameWantsHands]).
  List<HandSample> hands = const [];

  /// A legutóbbi kamera-képkocka (a fotóhoz).
  CameraImage? lastImage;

  /// Az arcok a legutóbbi képkockán (ha [wantFace]).
  List<FaceSample> faces = const [];

  bool _disposed = false;

  /// Forgatáskor a kép mérete megcserélődik – ilyenkor újrakezdjük a
  /// követést, hogy a régi helyzetből ne simítsunk az újba.
  Size? _imageSize;

  bool get mirror =>
      camera != null && VisionPoseService.mirrorSkeleton(camera!);

  Future<void> start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        error = 'No camera found.';
        notifyListeners();
        return;
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final c = CameraController(
        cam,
        // Nagyobb felbontáson a Vision pontjai pontosabbak, kevésbé remegnek.
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await c.initialize();
      await c.startImageStream(_onImage);
      if (_disposed) {
        await c.dispose();
        return;
      }
      controller = c;
      camera = cam;
      c.addListener(_followDeviceOrientation);
      await _followDeviceOrientation();
      notifyListeners();
    } on CameraException catch (e) {
      error = 'Camera error: ${e.description}';
      if (!_disposed) notifyListeners();
    }
  }

  DeviceOrientation? _appliedOrientation;

  /// A kép (és amit a Vision kap) kövesse a telefont, álló és fekvő
  /// helyzetben is egyenesen.
  ///
  /// A kamera plugin iOS 17 fölött a HÁTSÓ kamera szerint számolja a
  /// forgatási szöget; az elülső kameránál fekve így fejjel lefelé állna a
  /// kép. Ezért elülső kameránál a fekvő irányt megcseréljük, és erre
  /// zároljuk a felvételt.
  Future<void> _followDeviceOrientation() async {
    final c = controller;
    final cam = camera;
    if (c == null || cam == null || !c.value.isInitialized) return;
    final device = c.value.deviceOrientation;
    if (device == _appliedOrientation) return;
    _appliedOrientation = device;

    final front = cam.lensDirection == CameraLensDirection.front;
    final target = switch (device) {
      DeviceOrientation.landscapeLeft =>
        front
            ? DeviceOrientation.landscapeRight
            : DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight =>
        front
            ? DeviceOrientation.landscapeLeft
            : DeviceOrientation.landscapeRight,
      // Fejjel lefelé nem forog az app – maradunk állóban.
      _ => DeviceOrientation.portraitUp,
    };
    try {
      await c.lockCaptureOrientation(target);
    } on CameraException catch (e) {
      debugPrint('lockCaptureOrientation hiba: ${e.description}');
    }
  }

  Future<void> _onImage(CameraImage image) async {
    lastImage = image;
    final cam = camera;
    if (cam == null || _detector.isBusy) return;
    final result = await _detector.detect(
      image,
      face: wantFace,
      hands: gameWantsHands ? maxPeople * 2 : 0,
    );
    hands = result.hands;
    final raw = result.people;
    faces = result.faces;
    if (_disposed) return;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    if (size != _imageSize) {
      _imageSize = size;
      _tracker.reset();
    }
    final t = DateTime.now().microsecondsSinceEpoch / 1e6;
    people = _tracker.update(raw, t, maxPeople: maxPeople);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    controller?.removeListener(_followDeviceOrientation);
    controller?.dispose();
    _detector.close();
    super.dispose();
  }
}

class PoseCameraScope extends InheritedNotifier<PoseCamera> {
  const PoseCameraScope({
    super.key,
    required PoseCamera camera,
    required super.child,
  }) : super(notifier: camera);

  static PoseCamera of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PoseCameraScope>()!.notifier!;
}

/// Élő kamerakép [dim] erősséggel elsötétítve, rajta mindenki csontváza.
class PoseCameraBackground extends StatelessWidget {
  const PoseCameraBackground({super.key, this.dim = 0.72});

  final double dim;

  @override
  Widget build(BuildContext context) {
    final cam = PoseCameraScope.of(context);
    final c = cam.controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (c != null)
          _preview(
            c,
            MediaQuery.orientationOf(context) == Orientation.landscape,
          ),
        ColoredBox(color: Colors.black.withValues(alpha: dim)),
        if (c != null)
          for (final person in cam.people)
            CustomPaint(
              key: ValueKey(person.id),
              painter: SkeletonPainter(frame: person.frame, mirror: cam.mirror),
            ),
        // A felismert kezek ujjai (játék közben) – így látszik, hogy figyeli.
        if (c != null && cam.hands.isNotEmpty)
          CustomPaint(painter: _HandsPainter(cam.hands)),
      ],
    );
  }

  /// BoxFit.cover – ugyanígy számol a [SkeletonPainter] is.
  Widget _preview(CameraController c, bool landscape) {
    final size = c.value.previewSize;
    if (size == null) return const SizedBox.shrink();
    final long = math.max(size.width, size.height);
    final short = math.min(size.width, size.height);
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: landscape ? long : short,
            height: landscape ? short : long,
            child: CameraPreview(c),
          ),
        ),
      ),
    );
  }
}

/// A kezek ujjcsontjai a kamerakép fölé (ugyanaz a BoxFit.cover vetítés,
/// mint a csontváznál).
class _HandsPainter extends CustomPainter {
  _HandsPainter(this.hands);

  final List<HandSample> hands;

  /// Ujjanként a pontok sorrendje (0 = csukló).
  static const List<List<int>> _chains = [
    [0, 1, 2, 3, 4],
    [0, 5, 6, 7, 8],
    [0, 9, 10, 11, 12],
    [0, 13, 14, 15, 16],
    [0, 17, 18, 19, 20],
    [5, 9, 13, 17],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final img = hands.first.imageSize;
    final iw = img.width, ih = img.height;
    if (iw <= 0 || ih <= 0) return;
    final scale = math.max(size.width / iw, size.height / ih);
    final dx = (size.width - iw * scale) / 2;
    final dy = (size.height - ih * scale) / 2;
    Offset map(Offset p) => Offset(p.dx * scale + dx, p.dy * scale + dy);

    final bone = Paint()
      ..color = const Color(0xFFE6D8CD)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final joint = Paint()..color = Colors.white;
    for (final h in hands) {
      if (h.points.length < 21) continue;
      for (final chain in _chains) {
        for (var i = 0; i + 1 < chain.length; i++) {
          final a = h.points[chain[i]], b = h.points[chain[i + 1]];
          if (a != null && b != null) canvas.drawLine(map(a), map(b), bone);
        }
      }
      for (final p in h.points) {
        if (p != null) canvas.drawCircle(map(p), 2.6, joint);
      }
    }
  }

  @override
  bool shouldRepaint(_HandsPainter old) => !identical(old.hands, hands);
}
