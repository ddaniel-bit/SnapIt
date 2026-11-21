import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Apple Liquid Glass vezérlők (iOS 26+; régebbi iOS-en a rendszer sima
/// gombjai). Natív UIKit nézetek, a Flutter kép fölé ágyazva.

/// Nagy, kapszula alakú Liquid Glass gomb SF Symbol ikonnal és felirattal
/// (natív `UIButton`, `.prominentGlass()` / `.glass()` – lásd AppDelegate).
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.symbol,
    required this.onTap,
    this.prominent = true,
    this.tint,
    this.height = 58,
    this.fontSize = 20,
  });

  final String label;

  /// SF Symbol neve, pl. `play.fill`, `camera.fill`.
  final String symbol;
  final VoidCallback? onTap;

  /// Kitöltött (színes) üveg, vagy átlátszó üveg.
  final bool prominent;
  final Color? tint;
  final double height;
  final double fontSize;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  MethodChannel? _channel;

  Map<String, Object?> get _params => {
    'title': widget.label,
    'symbol': widget.symbol,
    'prominent': widget.prominent,
    'enabled': widget.onTap != null,
    'fontSize': widget.fontSize,
    // Nyomáskor is a logó színe látszik, ne a rendszer kékje.
    'tint': (widget.tint ?? AppColors.accent).toARGB32(),
  };

  @override
  void didUpdateWidget(GlassButton old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label ||
        old.symbol != widget.symbol ||
        old.prominent != widget.prominent ||
        old.tint != widget.tint ||
        old.fontSize != widget.fontSize ||
        (old.onTap == null) != (widget.onTap == null)) {
      _channel?.invokeMethod('update', _params);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _created(int id) {
    _channel = MethodChannel('projekt/glass_button_$id')
      ..setMethodCallHandler((call) async {
        if (call.method == 'pressed') widget.onTap?.call();
      });
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.onTap,
          icon: const Icon(Icons.circle),
          label: Text(widget.label),
        ),
      );
    }
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: UiKitView(
        viewType: 'projekt/glass_button',
        creationParams: _params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
      ),
    );
  }
}

/// Kis Liquid Glass címke (nem gomb) a logó színében, pl. a póz neve.
/// Akkora, amekkora a szövege.
class GlassLabel extends StatelessWidget {
  const GlassLabel({
    super.key,
    required this.text,
    this.symbol,
    this.fontSize = 16,
    this.height = 38,
  });

  final String text;
  final String? symbol;
  final double fontSize;
  final double height;

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // A kapszula belső margója + az ikon helye.
    final width =
        painter.width + 36 + (symbol == null ? 0 : fontSize * 1.2 + 10);

    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Text(text, style: TextStyle(fontSize: fontSize)),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: UiKitView(
        key: ValueKey(text),
        viewType: 'projekt/glass_button',
        creationParams: {
          'title': text,
          if (symbol != null) 'symbol': symbol,
          'prominent': true,
          'enabled': true,
          'interactive': false,
          'fontSize': fontSize,
          'tint': AppColors.accent.toARGB32(),
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}

/// Kerek, csak ikonos Liquid Glass gomb (vissza, bezárás).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.symbol,
    required this.onTap,
    this.size = 44,
  });

  final String symbol;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CNButton.icon(
      icon: CNSymbol(symbol, size: size * 0.42, color: Colors.white),
      size: size,
      style: CNButtonStyle.glass,
      tint: AppColors.accent,
      onPressed: onTap,
    );
  }
}

/// Liquid Glass szegmentált vezérlő (natív `UISegmentedControl`) – a
/// kiválasztott elem mögötti „üveg" húzással is mozgatható.
class GlassSegmented extends StatelessWidget {
  const GlassSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.height = 40,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CNSegmentedControl(
        labels: labels,
        selectedIndex: index,
        onValueChanged: onChanged,
        height: height,
        color: AppColors.accent,
      ),
    );
  }
}
