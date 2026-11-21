import 'body_point.dart';
import 'vec2.dart';

/// Egy felismert testpont egyetlen képkockán.
class PoseKeypoint {
  const PoseKeypoint({
    required this.point,
    required this.x,
    required this.y,
    required this.z,
    required this.likelihood,
  });

  final BodyPoint point;

  /// Pixelkoordináta a *felállított* (rotáció után értelmezett) képen belül.
  final double x;
  final double y;

  /// Relatív mélység (a csípő közepéhez képest). Most nem használjuk,
  /// bővítés: 3D-alapú szögek / kamerához viszonyított testhelyzet.
  final double z;

  /// 0..1 megbízhatóság.
  final double likelihood;

  Vec2 get position => Vec2(x, y);

  bool isReliable(double minLikelihood) => likelihood >= minLikelihood;
}

/// Egy képkocka teljes pose-eredménye, ML Kit típusok nélkül.
class PoseFrame {
  const PoseFrame({
    required this.keypoints,
    required this.imageWidth,
    required this.imageHeight,
    required this.timestampMicros,
  });

  final Map<BodyPoint, PoseKeypoint> keypoints;

  /// Annak a képnek a mérete, amelyben a koordináták értelmezettek
  /// (már a szenzor-rotáció utáni, "álló" méret).
  final double imageWidth;
  final double imageHeight;

  /// Bővítés: erre épül majd a simítás és az ismétlés-szegmentálás.
  final int timestampMicros;

  PoseKeypoint? operator [](BodyPoint point) => keypoints[point];

  bool get isEmpty => keypoints.isEmpty;
}
