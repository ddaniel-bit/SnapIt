import 'dart:math' as math;

import 'body_point.dart';
import 'pose_frame.dart';
import 'vec2.dart';

/// E likelihood alatt egy pontot megbízhatatlannak tekintünk.
const double kMinLikelihood = 0.3;

/// A kijelzett ízületi szögek.
enum Joint {
  leftElbow,
  rightElbow,
  leftKnee,
  rightKnee,
  leftHip,
  rightHip,
  leftShoulder,
  rightShoulder,
}

/// Melyik három pontból számoljuk az adott ízület szögét: (kar1, csúcs, kar2).
const Map<Joint, (BodyPoint, BodyPoint, BodyPoint)> kJointChains = {
  Joint.leftElbow: (
    BodyPoint.leftShoulder,
    BodyPoint.leftElbow,
    BodyPoint.leftWrist,
  ),
  Joint.rightElbow: (
    BodyPoint.rightShoulder,
    BodyPoint.rightElbow,
    BodyPoint.rightWrist,
  ),
  Joint.leftKnee: (BodyPoint.leftHip, BodyPoint.leftKnee, BodyPoint.leftAnkle),
  Joint.rightKnee: (
    BodyPoint.rightHip,
    BodyPoint.rightKnee,
    BodyPoint.rightAnkle,
  ),
  Joint.leftHip: (
    BodyPoint.leftShoulder,
    BodyPoint.leftHip,
    BodyPoint.leftKnee,
  ),
  Joint.rightHip: (
    BodyPoint.rightShoulder,
    BodyPoint.rightHip,
    BodyPoint.rightKnee,
  ),
  Joint.leftShoulder: (
    BodyPoint.leftHip,
    BodyPoint.leftShoulder,
    BodyPoint.leftElbow,
  ),
  Joint.rightShoulder: (
    BodyPoint.rightHip,
    BodyPoint.rightShoulder,
    BodyPoint.rightElbow,
  ),
};

/// Tiszta geometriai számítások. Se Flutter, se ML Kit import.
///
/// Bővítés helye: ide jön majd az idősoros simítás (pl. EMA / One Euro filter)
/// és az ismétlés-szegmentálás.
class PoseGeometry {
  const PoseGeometry._();

  /// A `vertex` csúcsban bezárt szög fokban, 0..180 között.
  ///
  /// `null`, ha valamelyik szár nulla hosszúságú (elfajult eset).
  /// atan2-alapú, mert az acos numerikusan instabil a 0°/180° közelében.
  static double? angleAtDegrees(Vec2 a, Vec2 vertex, Vec2 b) {
    final v1 = a - vertex;
    final v2 = b - vertex;
    const epsilon = 1e-6;
    if (v1.length < epsilon || v2.length < epsilon) return null;

    final radians = math.atan2(v1.cross(v2).abs(), v1.dot(v2));
    return radians * 180 / math.pi;
  }

  /// Egyetlen ízület szöge a képkockából.
  ///
  /// `null`, ha bármelyik szükséges pont hiányzik vagy megbízhatatlan –
  /// a UI ilyenkor "--"-t ír ki.
  static double? jointAngle(
    PoseFrame frame,
    Joint joint, {
    double minLikelihood = kMinLikelihood,
  }) {
    final (aPoint, vertexPoint, bPoint) = kJointChains[joint]!;
    final a = frame[aPoint];
    final vertex = frame[vertexPoint];
    final b = frame[bPoint];

    if (a == null || vertex == null || b == null) return null;
    if (!a.isReliable(minLikelihood) ||
        !vertex.isReliable(minLikelihood) ||
        !b.isReliable(minLikelihood)) {
      return null;
    }

    // Megjegyzés: ez 2D-s, képsíkra vetített szög. A kamerához képest ferde
    // testhelyzetnél torzít – bővítés: z koordináta bevonása.
    return angleAtDegrees(a.position, vertex.position, b.position);
  }

  /// Az összes figyelt ízület szöge. Az érték `null`, ha nem megbízható.
  static Map<Joint, double?> jointAngles(
    PoseFrame frame, {
    double minLikelihood = kMinLikelihood,
  }) {
    return <Joint, double?>{
      for (final joint in Joint.values)
        joint: jointAngle(frame, joint, minLikelihood: minLikelihood),
    };
  }
}
