import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../ui/glass.dart';
import 'gaze_controller.dart';

/// Nézéssel is kiválasztható elem: amíg a játékos nézi, egy vonal fut körbe
/// rajta; ha körbeér, [onSelect] hívódik. Az érintést nem fogja el.
class GazeTarget extends StatefulWidget {
  const GazeTarget({
    super.key,
    required this.child,
    required this.onSelect,
    this.enabled = true,
    this.radius = 22,
    this.padding = 5,
  });

  final Widget child;
  final VoidCallback onSelect;
  final bool enabled;

  /// A körvonal sarokkerekítése (a gomb formájához).
  final double radius;

  /// Ennyivel a gomb körül fut a vonal.
  final double padding;

  @override
  State<GazeTarget> createState() => _GazeTargetState();
}

class _GazeTargetState extends State<GazeTarget> implements GazeTargetHandle {
  @override
  final ValueNotifier<double> progress = ValueNotifier(0);

  GazeController? _controller;
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final c = GazeScope.of(context);
    if (!identical(c, _controller)) {
      _controller?.unregister(this);
      _controller = c..register(this);
    }
  }

  @override
  void dispose() {
    _controller?.unregister(this);
    progress.dispose();
    super.dispose();
  }

  @override
  Rect? get globalRect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  bool get isOnTopRoute => mounted && (_route?.isCurrent ?? true);

  @override
  bool get enabled => widget.enabled;

  @override
  void onSelect() => widget.onSelect();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _RingPainter(
        progress,
        radius: widget.radius,
        padding: widget.padding,
      ),
      child: widget.child,
    );
  }
}

/// A körbefutó vonal: halvány sáv, rajta a feltöltődő fényes vonal.
class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, {required this.radius, required this.padding})
    : super(repaint: progress);

  final ValueNotifier<double> progress;
  final double radius;
  final double padding;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    if (p <= 0) return;

    final rect = (Offset.zero & size).inflate(padding);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius + padding)),
      );
    final PathMetric metric = path.computeMetrics().first;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = Colors.white.withValues(alpha: 0.18 * (p * 4).clamp(0.0, 1.0));
    canvas.drawPath(path, track);

    final arc = metric.extractPath(0, metric.length * p);
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.radius != radius || old.padding != padding;
}

/// [GlassSegmented] nézéssel: minden szegmens külön célpont.
class GazeSegmented extends StatelessWidget {
  const GazeSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.height = 40,
    this.enabled = true,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  /// Nézéssel választható-e (érintéssel mindig).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GlassSegmented(
          labels: labels,
          index: index,
          onChanged: onChanged,
          height: height,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: GazeTarget(
                      radius: height / 2 - 4,
                      padding: 2,
                      enabled: enabled && i != index,
                      onSelect: () => onChanged(i),
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
