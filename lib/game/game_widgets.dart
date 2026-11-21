import 'package:flutter/material.dart';

import '../ui/app_theme.dart';
import 'pose_scorer.dart';
import 'stick_figure.dart';
import 'target_pose.dart';

// A Picture mode és a játékmód közös elemei.

/// A póz fotója (ha nincs, a pálcikaember) lekerekített kártyán.
class ReferencePhoto extends StatelessWidget {
  const ReferencePhoto({
    super.key,
    required this.pose,
    required this.radius,
    this.badge,
  });

  final TargetPose pose;
  final double radius;

  /// Kis jel a sarokban (pl. „P1"), ha több póz van.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final photo = pose.photo;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null)
            Image.asset(
              photo,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            )
          else
            Padding(
              padding: const EdgeInsets.all(10),
              child: StickFigure(pose: pose),
            ),
          if (badge != null)
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Egy játékos pálcikaembere, fölötte a jele (P1…), alatta a százaléka.
class PlayerFigure extends StatelessWidget {
  const PlayerFigure({
    super.key,
    required this.pose,
    required this.label,
    required this.accuracy,
    required this.score,
    this.caption,
  });

  final TargetPose pose;
  final String? label;
  final double? accuracy;
  final PoseScore? score;

  /// Apró felirat alul (pl. a póz neve és a kért arc/kéz).
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final acc = accuracy;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Text(
            label!,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        StickFigure(pose: pose, score: score),
        if (label != null)
          Text(
            acc == null ? '–' : '${acc.round()}%',
            style: TextStyle(
              color: acc == null ? Colors.white38 : AppColors.forAccuracy(acc),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        if (caption != null)
          Text(
            caption!,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
      ],
    );
  }
}

class AccuracyPill extends StatelessWidget {
  const AccuracyPill({
    super.key,
    required this.accuracy,
    required this.missing,
  });

  final double? accuracy;

  /// Hány játékos nem látszik még.
  final int missing;

  @override
  Widget build(BuildContext context) {
    final acc = accuracy;
    final color = acc == null ? Colors.white54 : AppColors.forAccuracy(acc);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
          ),
          child: Text(
            acc == null ? 'Step into the frame' : 'Accuracy  ${acc.round()}%',
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (acc != null && missing > 0) ...[
          const SizedBox(height: 8),
          Text(
            missing == 1
                ? '1 player is not in the frame'
                : '$missing players are not in the frame',
            style: const TextStyle(color: AppColors.warn, fontSize: 14),
          ),
        ],
      ],
    );
  }
}
