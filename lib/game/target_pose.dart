import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/material.dart' show IconData, Icons;

import 'expression.dart';
import 'hand_shape.dart';

/// A célpóz ízületei – KÉPERNYŐ-oldal szerint (l = a képernyő bal oldalán
/// látszó végtag), mert a játékos a tükörképét igazítja a pálcikaemberhez.
enum Joint {
  head,
  lShoulder,
  rShoulder,
  lElbow,
  rElbow,
  lWrist,
  rWrist,
  lHip,
  rHip,
  lKnee,
  rKnee,
  lAnkle,
  rAnkle,
}

/// Egy összehasonlított szakasz (irány alapján) és a súlya a pontszámban.
class Limb {
  const Limb(this.from, this.to, this.weight);
  final Joint from;
  final Joint to;
  final double weight;
}

/// A pontozott szakaszok. A törzset a váll- és csípőközéppel külön kezeljük.
const List<Limb> kScoredLimbs = [
  Limb(Joint.lShoulder, Joint.lElbow, 1.0),
  Limb(Joint.lElbow, Joint.lWrist, 1.0),
  Limb(Joint.rShoulder, Joint.rElbow, 1.0),
  Limb(Joint.rElbow, Joint.rWrist, 1.0),
  Limb(Joint.lHip, Joint.lKnee, 0.7),
  Limb(Joint.lKnee, Joint.lAnkle, 0.5),
  Limb(Joint.rHip, Joint.rKnee, 0.7),
  Limb(Joint.rKnee, Joint.rAnkle, 0.5),
];

const double kTorsoWeight = 0.5;
const double kHeadWeight = 0.3;

/// Az arckifejezés súlya (kb. egy karszakasznyi).
const double kExpressionWeight = 1.0;

/// Egy kéz ujjtartásának súlya.
const double kHandWeight = 0.5;

/// Felsőtestes (karok + törzs, a láb nem számít) vagy teljes testes póz.
enum BodyMode {
  upper('Upper body'),
  full('Full body');

  const BodyMode(this.label);
  final String label;
}

enum PoseCategory {
  party('Party', Icons.celebration_rounded),
  couple('Couple', Icons.favorite_rounded),
  family('Family', Icons.family_restroom_rounded),
  casual('Casual', Icons.emoji_people_rounded);

  const PoseCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Egy kitalált póz: ízületpozíciók egy 1×1-es dobozban (x jobbra, y lefelé).
class TargetPose {
  const TargetPose({
    required this.name,
    required this.hint,
    required this.category,
    required this.mode,
    required this.expression,
    this.lHand = HandShape.any,
    this.rHand = HandShape.any,
    this.photoAsset,
    required this.joints,
  });

  final String name;
  final String hint;
  final PoseCategory category;
  final BodyMode mode;

  /// Az arckifejezés, ami a pózhoz tartozik.
  final Expression expression;

  /// A kép bal / jobb oldalán látszó kéz tartása (a fotók alapján).
  final HandShape lHand;
  final HandShape rHand;

  /// Felsőtestes póznál nincs térd és boka.
  final Map<Joint, Offset> joints;

  Offset operator [](Joint j) => joints[j]!;

  bool has(Joint j) => joints.containsKey(j);

  /// Saját fotó (pl. a játékmód mémjei); ha nincs, a név alapján keressük.
  final String? photoAsset;

  /// A póz fotója (referencia), ha van.
  String? get photo => photoAsset ?? _photos[name];

  static const Map<String, String> _photos = {
    'Y.M.C.A.': 'assets/poses/ymca.jpg',
    'Raise the Roof': 'assets/poses/raise_the_roof.jpg',
    'Selfie Time': 'assets/poses/selfie_time.jpg',
    'Blow a Kiss': 'assets/poses/blow_a_kiss.jpg',
    'Robot': 'assets/poses/robot.jpg',
    'Facepalm': 'assets/poses/facepalm.jpg',
    'Thinker': 'assets/poses/thinker.jpg',
    'Disco Inferno': 'assets/poses/disco_inferno.jpg',
    'Air Guitar': 'assets/poses/air_guitar.jpg',
    'Flamingo': 'assets/poses/flamingo.jpg',
    'Warrior': 'assets/poses/warrior.jpg',
    'Sumo': 'assets/poses/sumo.jpg',
    'Penguin': 'assets/poses/penguin.jpg',
    'Lightning Bolt': 'assets/poses/lightning_bolt.jpg',
    'Superhero': 'assets/poses/superhero.jpg',
    // Airplane: még nincs fotó – helyette a pálcikaember látszik nagyban.
  };

  /// Az adott kategória és mód első póza (determinisztikus – tesztekhez).
  static TargetPose forCategory(PoseCategory c, BodyMode mode) =>
      kPoses.firstWhere((p) => p.category == c && p.mode == mode);

  /// Az adott kategória és mód összes póza.
  static List<TargetPose> all(PoseCategory c, BodyMode mode) =>
      kPoses.where((p) => p.category == c && p.mode == mode).toList();

  /// Játékosonként egy-egy véletlen póz a kategóriából: amíg van eltérő
  /// póz, mindenki mást kap (utána ismétlődnek). Az első lehetőleg nem
  /// ugyanaz, mint [except] (az előző kör első póza).
  static List<TargetPose> forPlayers(
    PoseCategory c,
    BodyMode mode,
    int players, {
    TargetPose? except,
    math.Random? rng,
  }) {
    final random = rng ?? math.Random();
    final options = all(c, mode)..shuffle(random);
    if (except != null && options.length > 1 && options.first == except) {
      options.add(options.removeAt(0));
    }
    return [for (var i = 0; i < players; i++) options[i % options.length]];
  }

  /// Véletlen póz a kategóriából – ha lehet, nem ugyanaz, mint [except].
  static TargetPose random(
    PoseCategory c,
    BodyMode mode, {
    TargetPose? except,
    math.Random? rng,
  }) {
    final options = all(c, mode);
    final fresh = options.where((p) => p != except).toList();
    final pool = fresh.isEmpty ? options : fresh;
    return pool[(rng ?? math.Random()).nextInt(pool.length)];
  }
}

// Álló alapalak – a pózok ebből térnek el.
const _head = Offset(0.50, 0.13);
const _lShoulder = Offset(0.40, 0.25);
const _rShoulder = Offset(0.60, 0.25);
const _lHip = Offset(0.44, 0.52);
const _rHip = Offset(0.56, 0.52);
const _lKnee = Offset(0.44, 0.72);
const _lAnkle = Offset(0.44, 0.92);

// A felsőtest ízületei, a karok nélkül (minden pózban ugyanaz).
const _torso = {
  Joint.head: _head,
  Joint.lShoulder: _lShoulder,
  Joint.rShoulder: _rShoulder,
  Joint.lHip: _lHip,
  Joint.rHip: _rHip,
};

const List<TargetPose> kPoses = [
  // ── Felsőtestes pózok ──────────────────────────────────────────────
  TargetPose(
    name: 'Y.M.C.A.',
    hint: 'Throw both arms up in a big Y!',
    category: PoseCategory.party,
    mode: BodyMode.upper,
    expression: Expression.smile,
    lHand: HandShape.open,
    rHand: HandShape.open,
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.31, 0.13),
      Joint.lWrist: Offset(0.22, 0.02),
      Joint.rElbow: Offset(0.69, 0.13),
      Joint.rWrist: Offset(0.78, 0.02),
    },
  ),
  TargetPose(
    name: 'Selfie Time',
    hint: 'Hold the phone up high, peace sign by your face',
    category: PoseCategory.couple,
    mode: BodyMode.upper,
    expression: Expression.kiss,
    lHand: HandShape.peace,
    joints: {
      Joint.head: Offset(0.52, 0.13),
      Joint.lShoulder: _lShoulder,
      Joint.rShoulder: _rShoulder,
      Joint.lHip: _lHip,
      Joint.rHip: _rHip,
      Joint.lElbow: Offset(0.31, 0.37),
      Joint.lWrist: Offset(0.34, 0.17),
      Joint.rElbow: Offset(0.72, 0.15),
      Joint.rWrist: Offset(0.81, 0.05),
    },
  ),
  TargetPose(
    name: 'Airplane',
    hint: 'Arms out like wings – and bank to the side!',
    category: PoseCategory.family,
    mode: BodyMode.upper,
    expression: Expression.wink,
    lHand: HandShape.open,
    rHand: HandShape.open,
    joints: {
      Joint.head: Offset(0.51, 0.12),
      Joint.lShoulder: Offset(0.40, 0.27),
      Joint.rShoulder: Offset(0.60, 0.23),
      Joint.lHip: _lHip,
      Joint.rHip: _rHip,
      Joint.lElbow: Offset(0.26, 0.32),
      Joint.lWrist: Offset(0.12, 0.37),
      Joint.rElbow: Offset(0.74, 0.18),
      Joint.rWrist: Offset(0.88, 0.13),
    },
  ),
  TargetPose(
    name: 'Facepalm',
    hint: 'Oh no… slap your forehead, other arm down',
    category: PoseCategory.casual,
    mode: BodyMode.upper,
    expression: Expression.surprised,
    lHand: HandShape.open,
    joints: {
      Joint.head: Offset(0.50, 0.14),
      Joint.lShoulder: _lShoulder,
      Joint.rShoulder: _rShoulder,
      Joint.lHip: _lHip,
      Joint.rHip: _rHip,
      Joint.lElbow: Offset(0.29, 0.16),
      Joint.lWrist: Offset(0.45, 0.10),
      Joint.rElbow: Offset(0.65, 0.38),
      Joint.rWrist: Offset(0.68, 0.51),
    },
  ),

  // ── Teljes testes pózok ────────────────────────────────────────────
  TargetPose(
    name: 'Disco Inferno',
    hint: 'Point to the sky, hand on hip, kick one leg out',
    category: PoseCategory.party,
    mode: BodyMode.full,
    expression: Expression.kiss,
    lHand: HandShape.point,
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.31, 0.14),
      Joint.lWrist: Offset(0.22, 0.03),
      Joint.rElbow: Offset(0.71, 0.37),
      Joint.rWrist: Offset(0.57, 0.49),
      Joint.lKnee: Offset(0.42, 0.72),
      Joint.lAnkle: Offset(0.41, 0.92),
      Joint.rKnee: Offset(0.62, 0.71),
      Joint.rAnkle: Offset(0.69, 0.90),
    },
  ),
  TargetPose(
    name: 'Flamingo',
    hint: 'Stand on one leg, other knee out, arms spread like wings',
    category: PoseCategory.couple,
    mode: BodyMode.full,
    expression: Expression.wink,
    lHand: HandShape.open,
    rHand: HandShape.open,
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.27, 0.18),
      Joint.lWrist: Offset(0.16, 0.12),
      Joint.rElbow: Offset(0.73, 0.18),
      Joint.rWrist: Offset(0.84, 0.12),
      Joint.lKnee: _lKnee,
      Joint.lAnkle: _lAnkle,
      Joint.rKnee: Offset(0.72, 0.62),
      Joint.rAnkle: Offset(0.50, 0.71),
    },
  ),
  TargetPose(
    name: 'Sumo',
    hint: 'Wide squat, knees out, hands on your knees',
    category: PoseCategory.family,
    mode: BodyMode.full,
    expression: Expression.surprised,
    joints: {
      Joint.head: Offset(0.50, 0.18),
      Joint.lShoulder: Offset(0.40, 0.30),
      Joint.rShoulder: Offset(0.60, 0.30),
      Joint.lHip: Offset(0.43, 0.56),
      Joint.rHip: Offset(0.57, 0.56),
      Joint.lElbow: Offset(0.30, 0.44),
      Joint.lWrist: Offset(0.28, 0.62),
      Joint.rElbow: Offset(0.70, 0.44),
      Joint.rWrist: Offset(0.72, 0.62),
      Joint.lKnee: Offset(0.27, 0.66),
      Joint.lAnkle: Offset(0.26, 0.88),
      Joint.rKnee: Offset(0.73, 0.66),
      Joint.rAnkle: Offset(0.74, 0.88),
    },
  ),
  TargetPose(
    name: 'Lightning Bolt',
    hint: 'Point to the sky like the fastest man alive',
    category: PoseCategory.casual,
    mode: BodyMode.full,
    expression: Expression.smile,
    lHand: HandShape.fist,
    rHand: HandShape.point,
    joints: {
      Joint.head: Offset(0.52, 0.13),
      Joint.lShoulder: _lShoulder,
      Joint.rShoulder: _rShoulder,
      Joint.lHip: _lHip,
      Joint.rHip: _rHip,
      Joint.lElbow: Offset(0.27, 0.28),
      Joint.lWrist: Offset(0.36, 0.17),
      Joint.rElbow: Offset(0.70, 0.17),
      Joint.rWrist: Offset(0.80, 0.09),
      Joint.lKnee: Offset(0.41, 0.72),
      Joint.lAnkle: Offset(0.37, 0.92),
      Joint.rKnee: Offset(0.58, 0.72),
      Joint.rAnkle: Offset(0.60, 0.92),
    },
  ),

  // ── Még felsőtestes pózok ──────────────────────────────────────────
  TargetPose(
    name: 'Raise the Roof',
    hint: 'Elbows out, palms up – push the ceiling higher!',
    category: PoseCategory.party,
    mode: BodyMode.upper,
    expression: Expression.smile,
    lHand: HandShape.open,
    rHand: HandShape.open,
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.27, 0.20),
      Joint.lWrist: Offset(0.28, 0.05),
      Joint.rElbow: Offset(0.73, 0.20),
      Joint.rWrist: Offset(0.72, 0.05),
    },
  ),
  TargetPose(
    name: 'Blow a Kiss',
    hint: 'Send a kiss from your lips out to the side',
    category: PoseCategory.couple,
    mode: BodyMode.upper,
    expression: Expression.kiss,
    rHand: HandShape.open,
    joints: {
      Joint.head: Offset(0.49, 0.13),
      Joint.lShoulder: _lShoulder,
      Joint.rShoulder: _rShoulder,
      Joint.lHip: _lHip,
      Joint.rHip: _rHip,
      Joint.lElbow: Offset(0.37, 0.39),
      Joint.lWrist: Offset(0.37, 0.52),
      Joint.rElbow: Offset(0.70, 0.33),
      Joint.rWrist: Offset(0.83, 0.24),
    },
  ),
  TargetPose(
    name: 'Robot',
    hint: 'One arm bent up, the other bent down – beep boop!',
    category: PoseCategory.family,
    mode: BodyMode.upper,
    expression: Expression.surprised,
    lHand: HandShape.open,
    rHand: HandShape.open,
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.25, 0.25),
      Joint.lWrist: Offset(0.25, 0.11),
      Joint.rElbow: Offset(0.75, 0.25),
      Joint.rWrist: Offset(0.75, 0.39),
    },
  ),
  TargetPose(
    name: 'Thinker',
    hint: 'Hand on your chin, other arm across your belly',
    category: PoseCategory.casual,
    mode: BodyMode.upper,
    expression: Expression.wink,
    joints: {
      Joint.head: Offset(0.49, 0.14),
      Joint.lShoulder: _lShoulder,
      Joint.rShoulder: _rShoulder,
      Joint.lHip: _lHip,
      Joint.rHip: _rHip,
      Joint.lElbow: Offset(0.37, 0.40),
      Joint.lWrist: Offset(0.47, 0.20),
      Joint.rElbow: Offset(0.62, 0.43),
      Joint.rWrist: Offset(0.40, 0.45),
    },
  ),

  // ── Még teljes testes pózok ────────────────────────────────────────
  TargetPose(
    name: 'Air Guitar',
    hint: 'Wide stance, one hand on the neck, the other strums',
    category: PoseCategory.party,
    mode: BodyMode.full,
    expression: Expression.surprised,
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.32, 0.40),
      Joint.lWrist: Offset(0.45, 0.46),
      Joint.rElbow: Offset(0.71, 0.33),
      Joint.rWrist: Offset(0.82, 0.38),
      Joint.lKnee: Offset(0.36, 0.72),
      Joint.lAnkle: Offset(0.31, 0.92),
      Joint.rKnee: Offset(0.64, 0.72),
      Joint.rAnkle: Offset(0.69, 0.92),
    },
  ),
  TargetPose(
    name: 'Warrior',
    hint: 'Deep lunge to the side, arms straight out',
    category: PoseCategory.couple,
    mode: BodyMode.full,
    expression: Expression.kiss,
    lHand: HandShape.open,
    rHand: HandShape.open,
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.26, 0.25),
      Joint.lWrist: Offset(0.12, 0.25),
      Joint.rElbow: Offset(0.74, 0.25),
      Joint.rWrist: Offset(0.88, 0.25),
      Joint.lKnee: Offset(0.29, 0.64),
      Joint.lAnkle: Offset(0.29, 0.88),
      Joint.rKnee: Offset(0.66, 0.70),
      Joint.rAnkle: Offset(0.77, 0.88),
    },
  ),
  TargetPose(
    name: 'Penguin',
    hint: 'Feet together, arms stiff like flippers',
    category: PoseCategory.family,
    mode: BodyMode.full,
    expression: Expression.wink,
    lHand: HandShape.open,
    rHand: HandShape.open,
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.34, 0.38),
      Joint.lWrist: Offset(0.28, 0.50),
      Joint.rElbow: Offset(0.66, 0.38),
      Joint.rWrist: Offset(0.72, 0.50),
      Joint.lKnee: Offset(0.47, 0.72),
      Joint.lAnkle: Offset(0.48, 0.92),
      Joint.rKnee: Offset(0.53, 0.72),
      Joint.rAnkle: Offset(0.52, 0.92),
    },
  ),
  TargetPose(
    name: 'Superhero',
    hint: 'Fists on your hips, chest out, feet apart',
    category: PoseCategory.casual,
    mode: BodyMode.full,
    expression: Expression.smile,
    lHand: HandShape.fist,
    rHand: HandShape.fist,
    joints: {
      ..._torso,
      Joint.lElbow: Offset(0.28, 0.38),
      Joint.lWrist: Offset(0.42, 0.50),
      Joint.rElbow: Offset(0.72, 0.38),
      Joint.rWrist: Offset(0.58, 0.50),
      Joint.lKnee: Offset(0.39, 0.72),
      Joint.lAnkle: Offset(0.35, 0.92),
      Joint.rKnee: Offset(0.61, 0.72),
      Joint.rAnkle: Offset(0.65, 0.92),
    },
  ),
];
