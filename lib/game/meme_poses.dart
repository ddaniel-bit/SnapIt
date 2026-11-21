import 'dart:ui' show Offset;

import 'expression.dart';
import 'hand_shape.dart';
import 'target_pose.dart';

// A játékmód mémjei (assets/memes). Mind felsőtestes – a mémek közeliek,
// így a játékosok közel állhatnak a kamerához. A „kép bal/jobb oldala" itt is
// úgy értendő, ahogy a képen látszik (a játékos a tükörképét igazítja hozzá).

const _head = Offset(0.50, 0.13);
const _lShoulder = Offset(0.40, 0.25);
const _rShoulder = Offset(0.60, 0.25);
const _lHip = Offset(0.44, 0.52);
const _rHip = Offset(0.56, 0.52);

const _torso = {
  Joint.head: _head,
  Joint.lShoulder: _lShoulder,
  Joint.rShoulder: _rShoulder,
  Joint.lHip: _lHip,
  Joint.rHip: _rHip,
};

// Lazán lelógó karok.
const _armsDown = {
  Joint.lElbow: Offset(0.37, 0.39),
  Joint.lWrist: Offset(0.37, 0.52),
  Joint.rElbow: Offset(0.63, 0.39),
  Joint.rWrist: Offset(0.63, 0.52),
};

const List<TargetPose> kMemePoses = [
  TargetPose(
    name: 'Alpha Stance',
    hint: 'Arms down and out, hands open – ready for anything',
    category: PoseCategory.casual,
    mode: BodyMode.upper,
    expression: Expression.neutral,
    lHand: HandShape.open,
    rHand: HandShape.open,
    photoAsset: 'assets/memes/m1.jpg',
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.32, 0.38),
      Joint.lWrist: Offset(0.27, 0.50),
      Joint.rElbow: Offset(0.68, 0.38),
      Joint.rWrist: Offset(0.73, 0.50),
    },
  ),
  TargetPose(
    name: 'Spider-Man Point',
    hint: 'Point straight at the side, other fist at your belly',
    category: PoseCategory.party,
    mode: BodyMode.upper,
    expression: Expression.surprised,
    lHand: HandShape.fist,
    rHand: HandShape.point,
    photoAsset: 'assets/memes/m2.jpg',
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.34, 0.40),
      Joint.lWrist: Offset(0.45, 0.42),
      Joint.rElbow: Offset(0.73, 0.27),
      Joint.rWrist: Offset(0.87, 0.28),
    },
  ),
  TargetPose(
    name: 'Hmmm…',
    hint: 'Squint and purse your lips – suspicious!',
    category: PoseCategory.casual,
    mode: BodyMode.upper,
    expression: Expression.kiss,
    photoAsset: 'assets/memes/m3.jpg',
    joints: {..._torso, ..._armsDown},
  ),
  TargetPose(
    name: 'Who, Me?',
    hint: 'Point at your own chest, eyebrows up',
    category: PoseCategory.casual,
    mode: BodyMode.upper,
    expression: Expression.surprised,
    rHand: HandShape.point,
    photoAsset: 'assets/memes/m4.jpg',
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.37, 0.39),
      Joint.lWrist: Offset(0.37, 0.52),
      Joint.rElbow: Offset(0.66, 0.40),
      Joint.rWrist: Offset(0.55, 0.30),
    },
  ),
  TargetPose(
    name: 'Shocked Monkey',
    hint: 'Clasp your hands at your chest – wide-eyed!',
    category: PoseCategory.family,
    mode: BodyMode.upper,
    expression: Expression.surprised,
    photoAsset: 'assets/memes/m5.jpg',
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.36, 0.42),
      Joint.lWrist: Offset(0.48, 0.35),
      Joint.rElbow: Offset(0.64, 0.42),
      Joint.rWrist: Offset(0.52, 0.35),
    },
  ),
  TargetPose(
    name: 'Laughing Monkey',
    hint: 'Laugh out loud with your mouth wide open!',
    category: PoseCategory.party,
    mode: BodyMode.upper,
    expression: Expression.smile,
    photoAsset: 'assets/memes/m6.jpg',
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.35, 0.39),
      Joint.lWrist: Offset(0.40, 0.52),
      Joint.rElbow: Offset(0.65, 0.39),
      Joint.rWrist: Offset(0.60, 0.52),
    },
  ),
  TargetPose(
    name: 'Chill Guy',
    hint: 'Hands in your pockets, smug little smile',
    category: PoseCategory.casual,
    mode: BodyMode.upper,
    expression: Expression.smile,
    photoAsset: 'assets/memes/m7.jpg',
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.34, 0.39),
      Joint.lWrist: Offset(0.42, 0.51),
      Joint.rElbow: Offset(0.66, 0.39),
      Joint.rWrist: Offset(0.58, 0.51),
    },
  ),
  TargetPose(
    name: 'Bliss Monkey',
    hint: 'Close your eyes and enjoy the moment',
    category: PoseCategory.family,
    mode: BodyMode.upper,
    expression: Expression.eyesClosed,
    photoAsset: 'assets/memes/m8.jpg',
    joints: {
      Joint.head: Offset(0.50, 0.12),
      Joint.lShoulder: _lShoulder,
      Joint.rShoulder: _rShoulder,
      Joint.lHip: _lHip,
      Joint.rHip: _rHip,
      ..._armsDown,
    },
  ),
  TargetPose(
    name: 'That\'s Him!',
    hint: 'Point at the screen, drink in the other hand',
    category: PoseCategory.party,
    mode: BodyMode.upper,
    expression: Expression.smile,
    lHand: HandShape.point,
    rHand: HandShape.fist,
    photoAsset: 'assets/memes/m9.jpg',
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.27, 0.25),
      Joint.lWrist: Offset(0.13, 0.22),
      Joint.rElbow: Offset(0.66, 0.40),
      Joint.rWrist: Offset(0.58, 0.30),
    },
  ),
  TargetPose(
    name: 'Oh No Monkey',
    hint: 'Both hands on top of your head',
    category: PoseCategory.family,
    mode: BodyMode.upper,
    expression: Expression.neutral,
    lHand: HandShape.open,
    rHand: HandShape.open,
    photoAsset: 'assets/memes/m10.jpg',
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.27, 0.15),
      Joint.lWrist: Offset(0.45, 0.04),
      Joint.rElbow: Offset(0.73, 0.15),
      Joint.rWrist: Offset(0.55, 0.04),
    },
  ),
  TargetPose(
    name: 'Thinking Monkey',
    hint: 'Finger on your lips… deep thoughts',
    category: PoseCategory.casual,
    mode: BodyMode.upper,
    expression: Expression.neutral,
    rHand: HandShape.point,
    photoAsset: 'assets/memes/m11.jpg',
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.37, 0.39),
      Joint.lWrist: Offset(0.37, 0.52),
      Joint.rElbow: Offset(0.62, 0.40),
      Joint.rWrist: Offset(0.52, 0.20),
    },
  ),
];
