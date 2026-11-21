import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'body_point.dart';
import 'pose_frame.dart';

/// Arckifejezés-mérőszámok egy arcról (Vision arcpontokból, az arc
/// méretétől függetlenül).
class FaceMetrics {
  const FaceMetrics({
    required this.mouthWidth,
    required this.mouthOpen,
    required this.smileCurve,
    required this.leftEyeOpen,
    required this.rightEyeOpen,
    required this.browRaise,
  });

  /// A száj szélessége a szemtávolsághoz mérve (mosolynál nő, csücsörítésnél
  /// csökken).
  final double mouthWidth;

  /// A belső ajkak távolsága a szájszélességhez mérve (nyitott száj).
  final double mouthOpen;

  /// Mennyivel vannak a szájszélek a száj közepe fölött (szemtávolságban).
  final double smileCurve;

  /// A szemek nyitottsága: magasság / szélesség.
  final double leftEyeOpen;
  final double rightEyeOpen;

  /// A szemöldök magassága a szem fölött (szemtávolságban).
  final double browRaise;
}

/// Egy arc egy képkockán: hol van, merre fordul a fej, és (ha megvannak a
/// pontok) milyen az arckifejezése.
class FaceSample {
  const FaceSample({
    required this.center,
    required this.size,
    required this.hx,
    required this.hy,
    required this.imageSize,
    this.metrics,
  });

  /// Az arc közepe és mérete képpixelben.
  final Offset center;
  final Size size;

  /// Az orr eltolódása a két szem közepétől, szemtávolságban (x jobbra,
  /// y lefelé). Ha a fej jobbra fordul, `hx` nő; ha lehajtja, `hy` nő.
  final double hx;
  final double hy;

  final Size imageSize;

  final FaceMetrics? metrics;
}

/// Egy kéz egy képkockán: a csuklója és az ujjai nyújtottsága.
class HandSample {
  const HandSample({
    required this.wrist,
    required this.confidence,
    required this.fingers,
    this.points = const [],
    this.imageSize = Size.zero,
  });

  /// A csukló képpixelben.
  final Offset wrist;
  final double confidence;

  /// Hüvelyk, mutató, középső, gyűrűs, kisujj: mennyire van kinyújtva
  /// (lásd `handData` az AppDelegate-ben); -1, ha az ujj nem látszik.
  final List<double> fingers;

  /// A kéz 21 pontja képpixelben (csukló, majd ujjanként tő→hegy: hüvelyk,
  /// mutató, középső, gyűrűs, kisujj); `null`, ha a pont nem látszik.
  final List<Offset?> points;

  final Size imageSize;
}

/// Egy képkocka eredménye: az emberek és (ha kértük) az arcok és a kezek.
class VisionResult {
  const VisionResult(this.people, this.faces, [this.hands = const []]);

  static const empty = VisionResult([], []);

  final List<PoseFrame> people;
  final List<FaceSample> faces;
  final List<HandSample> hands;
}

/// Apple Vision testpóz-felismerés (iOS), egyszerre több emberre.
///
/// A kamera BGRA képkockáját a natív oldal ([VisionPosePlugin] az
/// AppDelegate-ben) dolgozza fel; emberenként egy [PoseFrame] jön vissza.
class VisionPoseService {
  static const MethodChannel _channel = MethodChannel('projekt/vision_pose');

  static final Map<String, BodyPoint> _byName = {
    for (final p in BodyPoint.values) p.name: p,
  };

  /// Ennyi biztos pont kell, hogy embernek számítson (zaj ellen).
  static const int _minPoints = 5;

  bool _busy = false;
  bool _closed = false;

  /// Ha épp fut egy felismerés, a hívó dobja el az új képkockát.
  bool get isBusy => _busy;

  /// Az iOS kamera plugin az elülső kamera pufferét már tükrözve adja,
  /// ugyanúgy, mint a preview-t – a csontvázat nem kell tükrözni.
  static bool mirrorSkeleton(CameraDescription camera) => false;

  /// [face]: az arcokat is keressük; [hands]: legfeljebb ennyi kezet is
  /// (0: nem keresünk kezet).
  Future<VisionResult> detect(
    CameraImage image, {
    bool face = false,
    int hands = 0,
  }) async {
    if (_busy || _closed) return VisionResult.empty;
    if (image.format.group != ImageFormatGroup.bgra8888) {
      return VisionResult.empty;
    }
    _busy = true;
    try {
      final plane = image.planes.first;
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>('detect', {
            'bytes': plane.bytes,
            'width': image.width,
            'height': image.height,
            'bytesPerRow': plane.bytesPerRow,
            'face': face,
          });
      if (_closed || result == null) return VisionResult.empty;

      final ts = DateTime.now().microsecondsSinceEpoch;
      final people = <PoseFrame>[];
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      for (final person in (result['people'] as List<Object?>?) ?? const []) {
        final keypoints = <BodyPoint, PoseKeypoint>{};
        for (final raw in person! as List<Object?>) {
          final p = raw! as List<Object?>;
          final point = _byName[p[0]! as String];
          if (point == null) continue;
          keypoints[point] = PoseKeypoint(
            point: point,
            x: (p[1]! as num).toDouble(),
            y: (p[2]! as num).toDouble(),
            z: 0,
            likelihood: (p[3]! as num).toDouble(),
          );
        }
        final confident = keypoints.values
            .where((k) => k.likelihood >= 0.3)
            .length;
        if (confident < _minPoints) continue;
        people.add(
          PoseFrame(
            keypoints: keypoints,
            imageWidth: imageSize.width,
            imageHeight: imageSize.height,
            timestampMicros: ts,
          ),
        );
      }

      final faces = <FaceSample>[];
      for (final raw in (result['faces'] as List<Object?>?) ?? const []) {
        final f = (raw! as List<Object?>)
            .map((v) => (v! as num).toDouble())
            .toList();
        if (f.length < 6) continue;
        faces.add(
          FaceSample(
            center: Offset(f[0], f[1]),
            size: Size(f[2], f[3]),
            hx: f[4],
            hy: f[5],
            imageSize: imageSize,
            metrics: f.length >= 12
                ? FaceMetrics(
                    mouthWidth: f[6],
                    mouthOpen: f[7],
                    smileCurve: f[8],
                    leftEyeOpen: f[9],
                    rightEyeOpen: f[10],
                    browRaise: f[11],
                  )
                : null,
          ),
        );
      }
      final handList = <HandSample>[];
      for (final raw in (result['hands'] as List<Object?>?) ?? const []) {
        final v = (raw! as List<Object?>)
            .map((x) => (x! as num).toDouble())
            .toList();
        if (v.length < 8) continue;
        final points = <Offset?>[
          for (var j = 0; j < 21 && 8 + j * 3 + 2 < v.length; j++)
            v[8 + j * 3 + 2] > 0
                ? Offset(v[8 + j * 3], v[8 + j * 3 + 1])
                : null,
        ];
        handList.add(
          HandSample(
            wrist: Offset(v[0], v[1]),
            confidence: v[2],
            fingers: v.sublist(3, 8),
            points: points,
            imageSize: imageSize,
          ),
        );
      }
      return VisionResult(people, faces, handList);
    } catch (error) {
      debugPrint('VisionPoseService.detect hiba: $error');
      return VisionResult.empty;
    } finally {
      _busy = false;
    }
  }

  void close() => _closed = true;
}
