import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A logó üvegének színei (mokka/tópszín).
class BrandColors {
  const BrandColors._();

  static const Color light = Color(0xFFEDE2D9);
  static const Color mid = Color(0xFFB9A598);
  static const Color deep = Color(0xFF7D6A5F);
}

/// Üvegbetűs felirat a logó színeiben.
///
/// iOS 26-tól valódi Liquid Glass: a betűk körvonalára kerül az Apple üveg
/// anyaga (natív nézet, lásd `GlassTextPlatformView` az AppDelegate-ben).
/// Régebbi rendszeren Flutterben rajzolt utánzat ([_DrawnGlassText]).
class GlassText extends StatelessWidget {
  const GlassText(this.text, {super.key, this.fontSize = 44});

  final String text;
  final double fontSize;

  static final bool _nativeGlass = () {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    final m = RegExp(r'(\d+)\.').firstMatch(Platform.operatingSystemVersion);
    return (int.tryParse(m?.group(1) ?? '') ?? 0) >= 26;
  }();

  @override
  Widget build(BuildContext context) {
    if (!_nativeGlass) return _DrawnGlassText(text, fontSize: fontSize);

    // A natív nézetnek ugyanakkora hely, mint a Flutter-szövegnek.
    final painter = TextPainter(
      text: TextSpan(text: text, style: _DrawnGlassText.styleFor(fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    return SizedBox(
      width: painter.width,
      height: painter.height,
      child: UiKitView(
        viewType: 'projekt/glass_text',
        creationParams: {
          'text': text,
          'fontSize': fontSize,
          'tint': BrandColors.mid.withValues(alpha: 0.7).toARGB32(),
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}

/// Flutterben rajzolt üveghatás: áttetsző, színátmenetes kitöltés, fényes
/// csillanás a betűk felső részén, világos perem és lágy árnyék.
class _DrawnGlassText extends StatelessWidget {
  const _DrawnGlassText(this.text, {required this.fontSize});

  static TextStyle styleFor(double fontSize) => TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w900,
    letterSpacing: fontSize * 0.02,
    height: 1.1,
  );

  final String text;
  final double fontSize;

  TextStyle get _base => styleFor(fontSize);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Lágy árnyék alatta – „lebeg" a háttér fölött.
        Transform.translate(
          offset: Offset(0, fontSize * 0.08),
          child: Text(
            text,
            style: _base.copyWith(
              foreground: Paint()
                ..color = Colors.black.withValues(alpha: 0.45)
                ..maskFilter = MaskFilter.blur(
                  BlurStyle.normal,
                  fontSize * 0.12,
                ),
            ),
          ),
        ),
        // Áttetsző üvegtest: világosból sötétbe.
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BrandColors.light, BrandColors.mid, BrandColors.deep],
            stops: [0.0, 0.55, 1.0],
          ).createShader(r),
          child: Text(
            text,
            style: _base.copyWith(color: Colors.white.withValues(alpha: 0.88)),
          ),
        ),
        // Csillanás a betűk felső felén.
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.85),
              Colors.white.withValues(alpha: 0.15),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.38, 0.5],
          ).createShader(r),
          child: Text(text, style: _base.copyWith(color: Colors.white)),
        ),
        // Világos perem, mint az üveg széle.
        Text(
          text,
          style: _base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = fontSize * 0.025
              ..color = Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
