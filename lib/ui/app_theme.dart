import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  /// A Snap It! logó üvegének mokka/tópszíne – gombok, kijelölések.
  static const Color accent = Color(0xFF9C8475);

  /// Ugyanez világosan (sötét háttéren jól látszó kiemelés).
  static const Color accentLight = Color(0xFFDCCBBE);
  static const Color good = Color(0xFF4CD964);
  static const Color warn = Color(0xFFFF9F1C);
  static const Color bad = Color(0xFFFF5A4E);

  /// Átlós színátmenet: világosból sötétbe, enyhe árnyékkal.
  static BoxDecoration gradientBox(Color bg, {double radius = 22}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          bg,
          Color.lerp(bg, Colors.black, 0.20)!,
          Color.lerp(bg, Colors.black, 0.46)!,
        ],
        stops: const [0.0, 0.55, 1.0],
      ),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: bg.withValues(alpha: 0.3),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static Color forAccuracy(double pct) => pct >= 75
      ? good
      : pct >= 45
      ? warn
      : bad;
}
