import 'package:flutter/material.dart';

import 'body_point.dart';
import 'pose_frame.dart';
import 'pose_geometry.dart';
import 'preview_transform.dart';
import 'vec2.dart';

/// Csak rajzol: a [PoseFrame] pontjait és a csontvázvonalakat teszi a preview
/// fölé. Semmilyen számítást nem végez a koordináta-vetítésen kívül
/// (az is a [PreviewTransform]-ban van).
class SkeletonPainter extends CustomPainter {
  SkeletonPainter({
    required this.frame,
    required this.mirror,
    this.minLikelihood = kMinLikelihood,
    this.dimmed = false,
  });

  final PoseFrame? frame;

  /// Elülső kameránál a preview tükrözve látszik.
  final bool mirror;

  final double minLikelihood;

  /// Szürkén, halványan: a pontokat látjuk, de nem bízunk bennük (pl. túl
  /// messze áll a felhasználó) – ilyenkor semmit nem ítélünk.
  final bool dimmed;

  static const Color _dimmedColor = Color(0xFF9E9E9E);

  static const Color _leftColor = Color(0xFF4FC3F7);
  static const Color _rightColor = Color(0xFFFFB74D);
  static const Color _centerColor = Color(0xFF81C784);
  static const double _unreliableOpacity = 0.25;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = this.frame;
    if (frame == null || frame.isEmpty) return;

    final transform = PreviewTransform(
      imageWidth: frame.imageWidth,
      imageHeight: frame.imageHeight,
      canvasWidth: size.width,
      canvasHeight: size.height,
      mirror: mirror,
    );

    _paintBones(canvas, frame, transform);
    _paintPoints(canvas, frame, transform);
  }

  void _paintBones(Canvas canvas, PoseFrame frame, PreviewTransform transform) {
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final bone in kSkeletonBones) {
      final from = frame[bone.from];
      final to = frame[bone.to];
      if (from == null || to == null) continue;

      final reliable =
          from.isReliable(minLikelihood) && to.isReliable(minLikelihood);
      paint.color = _colorFor(bone.side, reliable);
      canvas.drawLine(
        _toOffset(transform.map(from.position)),
        _toOffset(transform.map(to.position)),
        paint,
      );
    }
  }

  void _paintPoints(
    Canvas canvas,
    PoseFrame frame,
    PreviewTransform transform,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final keypoint in frame.keypoints.values) {
      final reliable = keypoint.isReliable(minLikelihood);
      paint.color = _colorFor(_sideOf(keypoint.point), reliable);
      canvas.drawCircle(
        _toOffset(transform.map(keypoint.position)),
        reliable ? 5 : 3.5,
        paint,
      );
    }
  }

  Color _colorFor(BodySide side, bool reliable) {
    if (dimmed) return _dimmedColor.withValues(alpha: reliable ? 0.55 : 0.2);
    final base = switch (side) {
      BodySide.left => _leftColor,
      BodySide.right => _rightColor,
      BodySide.center => _centerColor,
    };
    return reliable ? base : base.withValues(alpha: _unreliableOpacity);
  }

  BodySide _sideOf(BodyPoint point) {
    if (point.name.startsWith('left')) return BodySide.left;
    if (point.name.startsWith('right')) return BodySide.right;
    return BodySide.center;
  }

  Offset _toOffset(Vec2 v) => Offset(v.x, v.y);

  @override
  bool shouldRepaint(SkeletonPainter oldDelegate) {
    return !identical(oldDelegate.frame, frame) ||
        oldDelegate.mirror != mirror ||
        oldDelegate.minLikelihood != minLikelihood ||
        oldDelegate.dimmed != dimmed;
  }
}
