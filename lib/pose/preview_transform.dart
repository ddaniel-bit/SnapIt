import 'dart:math' as math;

import 'vec2.dart';

/// A kamerakép koordinátáit vetíti a preview (canvas) koordinátáira.
///
/// Feltételezés: a preview `BoxFit.cover` módon tölti ki a canvast – pontosan
/// úgy, ahogy a `PoseCameraPage` kirakja a `CameraPreview`-t. A kép mérete itt
/// már a *felállított* (szenzor-rotációval korrigált) méret, mert az ML Kit is
/// abban a koordinátarendszerben adja vissza a landmarkokat.
///
/// Tiszta matek, Flutter import nélkül – unit-tesztelhető.
class PreviewTransform {
  PreviewTransform({
    required this.imageWidth,
    required this.imageHeight,
    required this.canvasWidth,
    required this.canvasHeight,
    this.mirror = false,
  }) : assert(imageWidth > 0 && imageHeight > 0);

  /// A felállított kamerakép mérete (amiben a landmark koordináták vannak).
  final double imageWidth;
  final double imageHeight;

  /// A rajzfelület mérete.
  final double canvasWidth;
  final double canvasHeight;

  /// Elülső kameránál a preview tükrözve jelenik meg, ezért a csontvázat is
  /// tükrözni kell, hogy illeszkedjen.
  final bool mirror;

  late final double _scale = math.max(
    canvasWidth / imageWidth,
    canvasHeight / imageHeight,
  );

  /// A cover-illesztés miatti levágás fele (negatív vagy nulla eltolás).
  late final double _offsetX = (canvasWidth - imageWidth * _scale) / 2;
  late final double _offsetY = (canvasHeight - imageHeight * _scale) / 2;

  Vec2 map(Vec2 imagePoint) {
    final x = imagePoint.x * _scale + _offsetX;
    final y = imagePoint.y * _scale + _offsetY;
    return Vec2(mirror ? canvasWidth - x : x, y);
  }

  /// Hosszméretek (pl. vonalvastagság) skálázásához.
  double get scale => _scale;
}
