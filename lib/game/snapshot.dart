import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// A kamera egy (BGRA) képkockájából kép – így néz ki, ahogy az előnézeten
/// (az elülső kamerán tükrözve, mint egy szelfi).
Future<ui.Image> imageFromCamera(CameraImage frame) {
  final plane = frame.planes.first;
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    plane.bytes,
    frame.width,
    frame.height,
    ui.PixelFormat.bgra8888,
    done.complete,
    rowBytes: plane.bytesPerRow,
  );
  return done.future;
}

/// A kép mentése a Fotók appba (natív oldal: AppDelegate, `projekt/photos`).
/// Igaz, ha sikerült; hamis, ha nincs engedély vagy hiba történt.
Future<bool> saveToPhotos(ui.Image image) async {
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return false;
  try {
    return await const MethodChannel(
          'projekt/photos',
        ).invokeMethod<bool>('save', png.buffer.asUint8List()) ??
        false;
  } on PlatformException {
    return false;
  }
}

/// A fotóra kerülő jelzések: jobb alul a Snap It! vízjel (logó + felirat,
/// áttetszően), bal alul az accuracy százalékban, színkódolva.
Future<ui.Image> stampPhoto(
  ui.Image photo, {
  required double accuracy,
  required bool team,
  String? badgeText,
}) async {
  final w = photo.width.toDouble(), h = photo.height.toDouble();
  final short = math.min(w, h);
  final margin = short * 0.045;
  final shadow = ui.Shadow(
    color: const ui.Color(0x99000000),
    blurRadius: short * 0.02,
    offset: ui.Offset(0, short * 0.004),
  );

  ui.Paragraph text(
    String s,
    double size,
    ui.Color color,
    ui.FontWeight weight, {
    double spacing = 0,
  }) {
    final b =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: size,
              fontWeight: weight,
              letterSpacing: spacing,
              shadows: [shadow],
            ),
          )
          ..addText(s);
    return b.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  // ── Vízjel (jobb alul) ──
  final logoPx = (short * 0.13).roundToDouble();
  final data = await rootBundle.load('media/snapit_logo.png');
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(),
    targetWidth: logoPx.toInt(),
    targetHeight: logoPx.toInt(),
  );
  final logo = (await codec.getNextFrame()).image;
  final brand = text(
    'Snap It!',
    logoPx * 0.46,
    const ui.Color(0xBFFFFFFF), // ~75% fehér
    ui.FontWeight.w800,
    spacing: logoPx * 0.01,
  );
  final gap = logoPx * 0.18;
  final brandLeft = w - margin - (logoPx + gap + brand.maxIntrinsicWidth);
  final brandTop = h - margin - logoPx;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawImage(photo, ui.Offset.zero, ui.Paint())
    ..drawImage(
      logo,
      ui.Offset(brandLeft, brandTop),
      ui.Paint()
        ..color =
            const ui.Color(0xD9FFFFFF) // ~85%
        ..filterQuality = ui.FilterQuality.high,
    )
    ..drawParagraph(
      brand,
      ui.Offset(
        brandLeft + logoPx + gap,
        brandTop + (logoPx - brand.height) / 2,
      ),
    );

  // ── Accuracy (bal alul): csak maga a szám, zöld üvegbetűkkel ──
  final pctText = badgeText ?? '${accuracy.round()}%';
  final pctSize = short * 0.095;
  final probe = text(
    pctText,
    pctSize,
    const ui.Color(0xFFFFFFFF),
    ui.FontWeight.w900,
  );
  // A szám alja egy vonalban a vízjel aljával.
  final origin = ui.Offset(margin, brandTop + logoPx - probe.height);
  _paintGlassText(canvas, pctText, pctSize, origin, probe.height);
  return recorder.endRecording().toImage(photo.width, photo.height);
}

/// Zöld „Liquid Glass" betűk a fotóra: lágy árnyék, áttetsző zöld
/// színátmenetes test, fényes csillanás a felső felén és világos perem.
void _paintGlassText(
  ui.Canvas canvas,
  String text,
  double size,
  ui.Offset at,
  double height,
) {
  ui.Paragraph build(ui.Paint foreground) {
    final b =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
          )
          ..pushStyle(
            ui.TextStyle(
              fontSize: size,
              fontWeight: ui.FontWeight.w900,
              letterSpacing: size * 0.01,
              foreground: foreground,
            ),
          )
          ..addText(text);
    return b.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  final top = at.dy, bottom = at.dy + height;
  canvas
    // Árnyék – „lebeg" a kép fölött.
    ..drawParagraph(
      build(
        ui.Paint()
          ..color = const ui.Color(0x80000000)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, size * 0.08),
      ),
      at + ui.Offset(0, size * 0.05),
    )
    // Áttetsző zöld üvegtest.
    ..drawParagraph(
      build(
        ui.Paint()
          ..shader = ui.Gradient.linear(
            ui.Offset(0, top),
            ui.Offset(0, bottom),
            [
              const ui.Color(0xF2C8F7D3),
              const ui.Color(0xE64CD964),
              const ui.Color(0xF01E8E3E),
            ],
            [0.0, 0.55, 1.0],
          ),
      ),
      at,
    )
    // Csillanás a betűk felső felén.
    ..drawParagraph(
      build(
        ui.Paint()
          ..shader = ui.Gradient.linear(
            ui.Offset(0, top),
            ui.Offset(0, top + height * 0.55),
            [const ui.Color(0xB3FFFFFF), const ui.Color(0x00FFFFFF)],
          ),
      ),
      at,
    )
    // Világos perem.
    ..drawParagraph(
      build(
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = size * 0.025
          ..color = const ui.Color(0xA6FFFFFF),
      ),
      at,
    );
}

/// A játékmód megosztható képe: a legjobban sikerült pillanat fotója, bal
/// alul a pontszám (zöld üvegbetűkkel), jobb alul a vízjel, felül a
/// „Beat me if you can!" felirat, a jobb felső sarokban a mém, amit utánzott.
Future<ui.Image> composeShareImage(
  ui.Image photo, {
  required int score,
  String? memeAsset,
}) async {
  final stamped = await stampPhoto(
    photo,
    accuracy: 0,
    team: false,
    badgeText: '$score pts',
  );
  final w = photo.width.toDouble(), h = photo.height.toDouble();
  final short = math.min(w, h);
  final margin = short * 0.045;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawImage(stamped, ui.Offset.zero, ui.Paint())
    // Felül halvány sötétítés a felirat alá.
    ..drawRect(
      ui.Rect.fromLTWH(0, 0, w, h * 0.22),
      ui.Paint()
        ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(0, h * 0.22), [
          const ui.Color(0x8C000000),
          const ui.Color(0x00000000),
        ]),
    );

  // A mém kicsiben a jobb felső sarokban.
  var titleRight = w - margin;
  if (memeAsset != null) {
    final data = await rootBundle.load(memeAsset);
    final side = (short * 0.24).roundToDouble();
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final meme = (await codec.getNextFrame()).image;
    final dst = ui.Rect.fromLTWH(w - margin - side, margin, side, side);
    // Középre vágva (cover).
    final mw = meme.width.toDouble(), mh = meme.height.toDouble();
    final crop = math.min(mw, mh);
    final src = ui.Rect.fromLTWH((mw - crop) / 2, (mh - crop) / 2, crop, crop);
    final rr = ui.RRect.fromRectAndRadius(dst, ui.Radius.circular(side * 0.14));
    canvas
      ..drawRRect(
        rr.shift(ui.Offset(0, short * 0.006)),
        ui.Paint()
          ..color = const ui.Color(0x66000000)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, short * 0.012),
      )
      ..save()
      ..clipRRect(rr)
      ..drawImageRect(
        meme,
        src,
        dst,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      )
      ..restore()
      ..drawRRect(
        rr,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = short * 0.005
          ..color = const ui.Color(0xCCFFFFFF),
      );
    titleRight = dst.left - margin * 0.6;
  }

  // „Beat me if you can!" – a felső sávban, a mém mellett.
  final titleSize = short * 0.085;
  final title =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(textDirection: ui.TextDirection.ltr, maxLines: 2),
        )
        ..pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFFFFFFFF),
            fontSize: titleSize,
            fontWeight: ui.FontWeight.w900,
            height: 1.05,
            shadows: [
              ui.Shadow(
                color: const ui.Color(0xB3000000),
                blurRadius: short * 0.02,
                offset: ui.Offset(0, short * 0.005),
              ),
            ],
          ),
        )
        ..addText('Beat me\nif you can!');
  final para = title.build()
    ..layout(ui.ParagraphConstraints(width: titleRight - margin));
  canvas.drawParagraph(para, ui.Offset(margin, margin));

  return recorder.endRecording().toImage(photo.width, photo.height);
}

/// A kép megosztása az iOS megosztó lapján (natív: AppDelegate,
/// `projekt/share`).
Future<void> shareImage(ui.Image image, String text) async {
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return;
  try {
    await const MethodChannel('projekt/share').invokeMethod<void>('share', {
      'png': png.buffer.asUint8List(),
      'text': text,
    });
  } on PlatformException {
    // A megosztás megszakadt – nem baj.
  }
}
