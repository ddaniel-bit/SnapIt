/// A testpontok saját, ML Kit-független reprezentációja.
///
/// A nevek szándékosan megegyeznek az ML Kit `PoseLandmarkType` neveivel, így a
/// service rétegben név alapján lehet konvertálni (lásd `PoseDetectorService`).
/// Ha később másik pose-modellre váltanánk (pl. MoveNet), csak a konverzió
/// változik, a geometria és a UI nem.
enum BodyPoint {
  nose,
  leftEyeInner,
  leftEye,
  leftEyeOuter,
  rightEyeInner,
  rightEye,
  rightEyeOuter,
  leftEar,
  rightEar,
  leftMouth,
  rightMouth,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftPinky,
  rightPinky,
  leftIndex,
  rightIndex,
  leftThumb,
  rightThumb,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  leftHeel,
  rightHeel,
  leftFootIndex,
  rightFootIndex,
}

/// Melyik testfél tartozik egy csonthoz – a rajzoló ez alapján színez.
enum BodySide { left, right, center }

/// Egy csontvázvonal: két testpont összekötése.
class Bone {
  const Bone(this.from, this.to, this.side);

  final BodyPoint from;
  final BodyPoint to;
  final BodySide side;
}

/// A kirajzolandó csontvázvonalak (topológia, nem rajzolási stílus).
const List<Bone> kSkeletonBones = <Bone>[
  // Arc (csak egy egyszerű váz: szem-fül-száj vonalakat kihagyjuk)
  Bone(BodyPoint.leftEar, BodyPoint.leftEye, BodySide.left),
  Bone(BodyPoint.leftEye, BodyPoint.nose, BodySide.left),
  Bone(BodyPoint.nose, BodyPoint.rightEye, BodySide.right),
  Bone(BodyPoint.rightEye, BodyPoint.rightEar, BodySide.right),

  // Törzs
  Bone(BodyPoint.leftShoulder, BodyPoint.rightShoulder, BodySide.center),
  Bone(BodyPoint.leftHip, BodyPoint.rightHip, BodySide.center),
  Bone(BodyPoint.leftShoulder, BodyPoint.leftHip, BodySide.left),
  Bone(BodyPoint.rightShoulder, BodyPoint.rightHip, BodySide.right),

  // Bal kar
  Bone(BodyPoint.leftShoulder, BodyPoint.leftElbow, BodySide.left),
  Bone(BodyPoint.leftElbow, BodyPoint.leftWrist, BodySide.left),
  Bone(BodyPoint.leftWrist, BodyPoint.leftThumb, BodySide.left),
  Bone(BodyPoint.leftWrist, BodyPoint.leftIndex, BodySide.left),
  Bone(BodyPoint.leftWrist, BodyPoint.leftPinky, BodySide.left),
  Bone(BodyPoint.leftIndex, BodyPoint.leftPinky, BodySide.left),

  // Jobb kar
  Bone(BodyPoint.rightShoulder, BodyPoint.rightElbow, BodySide.right),
  Bone(BodyPoint.rightElbow, BodyPoint.rightWrist, BodySide.right),
  Bone(BodyPoint.rightWrist, BodyPoint.rightThumb, BodySide.right),
  Bone(BodyPoint.rightWrist, BodyPoint.rightIndex, BodySide.right),
  Bone(BodyPoint.rightWrist, BodyPoint.rightPinky, BodySide.right),
  Bone(BodyPoint.rightIndex, BodyPoint.rightPinky, BodySide.right),

  // Bal láb
  Bone(BodyPoint.leftHip, BodyPoint.leftKnee, BodySide.left),
  Bone(BodyPoint.leftKnee, BodyPoint.leftAnkle, BodySide.left),
  Bone(BodyPoint.leftAnkle, BodyPoint.leftHeel, BodySide.left),
  Bone(BodyPoint.leftHeel, BodyPoint.leftFootIndex, BodySide.left),
  Bone(BodyPoint.leftAnkle, BodyPoint.leftFootIndex, BodySide.left),

  // Jobb láb
  Bone(BodyPoint.rightHip, BodyPoint.rightKnee, BodySide.right),
  Bone(BodyPoint.rightKnee, BodyPoint.rightAnkle, BodySide.right),
  Bone(BodyPoint.rightAnkle, BodyPoint.rightHeel, BodySide.right),
  Bone(BodyPoint.rightHeel, BodyPoint.rightFootIndex, BodySide.right),
  Bone(BodyPoint.rightAnkle, BodyPoint.rightFootIndex, BodySide.right),
];
