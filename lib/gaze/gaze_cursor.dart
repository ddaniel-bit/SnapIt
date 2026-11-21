import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pose/vision_pose_service.dart';

import 'gaze_controller.dart';

/// A nézés pontja a képernyőn: egy kis világító pötty; az irányító arca
/// körül egy halvány kör jelzi, ki irányít. Kalibráláskor középen kiírja,
/// hogy nézzen a közepére.
class GazeCursorLayer extends StatelessWidget {
  const GazeCursorLayer({super.key, required this.controller});

  final GazeController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          controller.screenSize = box.biggest;
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final p = controller.point;
              final face = controller.active ? controller.controllerFace : null;
              final marker = face == null
                  ? null
                  : _faceOnScreen(face, box.biggest);
              return Stack(
                children: [
                  if (marker != null)
                    Positioned.fromRect(
                      rect: marker,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.topCenter,
                        child: Transform.translate(
                          offset: const Offset(0, -14),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.visibility_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (controller.calibrating)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Look at the center',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (p != null)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 90),
                      left: p.dx - 11,
                      top: p.dy - 11,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.85),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.6),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Az arc helye a képernyőn – a kamerakép BoxFit.cover módon tölti ki.
  static Rect _faceOnScreen(FaceSample face, Size screen) {
    final img = face.imageSize;
    final scale = math.max(
      screen.width / img.width,
      screen.height / img.height,
    );
    final dx = (screen.width - img.width * scale) / 2;
    final dy = (screen.height - img.height * scale) / 2;
    final c = Offset(face.center.dx * scale + dx, face.center.dy * scale + dy);
    final r = math.max(face.size.width, face.size.height) * scale * 0.65;
    return Rect.fromCircle(center: c, radius: r);
  }
}
