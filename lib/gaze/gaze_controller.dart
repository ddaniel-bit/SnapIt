import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pose/pose_camera.dart';
import '../pose/vision_pose_service.dart';

/// Nézéses navigáció: az irányító fejirányából egy pontot számol a
/// képernyőn, és ha ez egy [GazeTarget]-en időzik [dwell] ideig, kiválasztja.
///
/// **Irányító:** az első arc, akit felvesz (ha több van, a legnagyobb, vagyis
/// a legközelebbi). Utána mindig őt követi – akkor is, ha más közelebb lép –,
/// amíg [lostAfter] ideig el nem tűnik; csak akkor választ újat.
///
/// A fej irányát az orr szemekhez viszonyított eltolódása adja (Vision arc-
/// pontok). Új irányítónál (és forgatáskor) újrakalibrál: azt a helyzetet
/// veszi a képernyő közepének, ahogy épp néz.
class GazeController extends ChangeNotifier {
  GazeController(this.camera) {
    camera.addListener(_onCamera);
  }

  final PoseCamera camera;

  /// Ennyi ideig kell egy opciót nézni.
  static const Duration dwell = Duration(milliseconds: 1100);

  /// Ha elnéz róla, ilyen gyorsan fogy vissza a kör.
  static const Duration decay = Duration(milliseconds: 500);

  /// Kiválasztás után ennyi ideig nem választ újra.
  static const Duration cooldown = Duration(milliseconds: 900);

  /// Fejfordítás → képernyő: mennyi képernyő-szélesség / -magasság egy
  /// szemtávolságnyi orr-eltolódás. (Kb. ±15° fordítás a képernyő széle.)
  static const double gainX = 3.5;
  static const double gainY = 5.0;

  /// Kalibrációhoz ennyi képkocka mediánja.
  static const int calibrationFrames = 12;

  /// Ennyi idő az irányító nélkül → új irányítót keres, újrakalibrál.
  static const Duration lostAfter = Duration(milliseconds: 1500);

  /// Az irányító arcát képkockáról képkockára ennyin belül keressük
  /// (az arc szélességének arányában).
  static const double followRadius = 1.2;

  /// A már nézett gomb ennyivel nagyobb területen „ragad" (px).
  static const double stickyMargin = 28;

  /// Ha a pont egyik gombon sincs, a legközelebbit veszi ennyin belül (px).
  static const double magnetRadius = 36;

  final Set<GazeTargetHandle> _targets = {};

  /// A nézés pontja a képernyőn (logikai pixel), ha van.
  Offset? point;

  /// Az irányító arca a legutóbbi képkockán (a kurzor-réteg megjelöli).
  FaceSample? controllerFace;

  /// A képernyő mérete (a kurzor-réteg állítja be). Ha a telefon
  /// átfordul (álló ↔ fekvő), újrakalibrálunk.
  Size get screenSize => _screenSize;
  set screenSize(Size size) {
    final wasLandscape = _screenSize.width > _screenSize.height;
    final isLandscape = size.width > size.height;
    if (_screenSize != Size.zero && wasLandscape != isLandscape) {
      _recalibrateAfterRotation();
    }
    _screenSize = size;
  }

  Size _screenSize = Size.zero;

  /// Forgatás után ennyi ideig várunk a kalibrálással, amíg a telefon (és a
  /// kamerakép tájolása) megáll.
  static const Duration settleAfterRotation = Duration(milliseconds: 1000);
  DateTime? _settleUntil;

  void _recalibrateAfterRotation() {
    _settleUntil = DateTime.now().add(settleAfterRotation);
    controllerFace = null;
    point = null;
    recalibrate();
  }

  /// Épp kalibrál (a kurzor-réteg kiírja: nézz a közepére).
  bool get calibrating =>
      active &&
      _neutral == null &&
      (controllerFace != null || _settleUntil != null);

  /// Van-e a jelenlegi oldalon nézéssel választható opció.
  bool get active => _targets.any((t) => t.isOnTopRoute && t.enabled);

  final _OneEuro _fx = _OneEuro(), _fy = _OneEuro();
  Offset? _neutral;
  final List<Offset> _calib = [];
  DateTime? _controllerSeen;
  DateTime? _lastTick;
  DateTime? _cooldownUntil;
  Size? _imageSize;
  GazeTargetHandle? _hovered;

  void register(GazeTargetHandle t) => _targets.add(t);
  void unregister(GazeTargetHandle t) {
    _targets.remove(t);
    if (identical(_hovered, t)) _hovered = null;
  }

  /// Újrakalibrálás kérése (pl. ha elcsúszott).
  void recalibrate() {
    _neutral = null;
    _calib.clear();
    _fx.reset();
    _fy.reset();
  }

  /// Az irányító elengedése: a következő képkockán új irányítót választ.
  void releaseController() {
    controllerFace = null;
    point = null;
    recalibrate();
  }

  void _onCamera() {
    final isActive = active;
    camera.gazeWantsFace = isActive;
    final now = DateTime.now();
    final dt = _lastTick == null
        ? 0.0
        : now.difference(_lastTick!).inMicroseconds / 1e6;
    _lastTick = now;

    if (!isActive) {
      if (point != null) {
        point = null;
        notifyListeners();
      }
      _hovered = null;
      _decayAll(dt, except: null);
      return;
    }

    final face = _pickController(camera.faces, now);
    if (face == null) {
      point = null;
      _hovered = null;
      _decayAll(dt, except: null);
      notifyListeners();
      return;
    }
    _update(face, now);

    final hovered = _hitTest(point);
    _hovered = hovered;

    final coolingDown = _cooldownUntil != null && now.isBefore(_cooldownUntil!);
    if (hovered != null && !coolingDown) {
      hovered.progress.value =
          (hovered.progress.value + dt * 1e6 / dwell.inMicroseconds).clamp(
            0.0,
            1.0,
          );
      if (hovered.progress.value >= 1) {
        _cooldownUntil = now.add(cooldown);
        for (final t in _targets) {
          t.progress.value = 0;
        }
        _hovered = null;
        hovered.onSelect();
      }
    }
    _decayAll(dt, except: hovered);
    notifyListeners();
  }

  /// Az irányító megkeresése a képkocka arcai között.
  FaceSample? _pickController(List<FaceSample> faces, DateTime now) {
    final current = controllerFace;

    if (current != null) {
      // Forgatáskor más a kép – új irányítót keresünk.
      if (faces.isNotEmpty && faces.first.imageSize != current.imageSize) {
        releaseController();
        return _pickController(faces, now);
      }
      FaceSample? best;
      var bestDist = double.infinity;
      for (final f in faces) {
        final d = (f.center - current.center).distance;
        final limit = math.max(current.size.width, 1) * followRadius;
        if (d <= limit && d < bestDist) {
          best = f;
          bestDist = d;
        }
      }
      if (best != null) {
        controllerFace = best;
        _controllerSeen = now;
        return best;
      }
      // Átmenetileg nem látszik: kivárunk, nem ugrunk át másra.
      if (_controllerSeen != null &&
          now.difference(_controllerSeen!) <= lostAfter) {
        return null;
      }
      releaseController();
    }

    if (faces.isEmpty) return null;
    // Új irányító: a legnagyobb (legközelebbi) arc.
    final first = faces.reduce(
      (a, b) =>
          a.size.width * a.size.height >= b.size.width * b.size.height ? a : b,
    );
    controllerFace = first;
    _controllerSeen = now;
    _imageSize = first.imageSize;
    recalibrate();
    return first;
  }

  void _update(FaceSample face, DateTime now) {
    if (face.imageSize != _imageSize) {
      // A kamerakép is átfordult – újra kivárjuk, hogy megálljon.
      final first = _imageSize == null;
      _imageSize = face.imageSize;
      if (!first) _settleUntil = now.add(settleAfterRotation);
      recalibrate();
    }
    // Forgatás után: amíg a telefon mozog, nem kalibrálunk (és nem mutatunk).
    final settle = _settleUntil;
    if (settle != null) {
      if (now.isBefore(settle)) {
        point = null;
        return;
      }
      _settleUntil = null;
      recalibrate();
    }
    final t = now.microsecondsSinceEpoch / 1e6;
    final raw = Offset(_fx.filter(face.hx, t), _fy.filter(face.hy, t));

    if (_neutral == null) {
      _calib.add(raw);
      if (_calib.length >= calibrationFrames) {
        _neutral = Offset(
          _median(_calib.map((o) => o.dx)),
          _median(_calib.map((o) => o.dy)),
        );
        _calib.clear();
      }
      point = null;
      return;
    }

    // Az elülső kamera képe tükrözött (mint egy tükör): ha a játékos jobbra
    // fordítja a fejét, az orra a képen is jobbra mozdul – és a képernyő
    // jobb oldalára néz.
    final d = raw - _neutral!;
    final x = (0.5 + d.dx * gainX).clamp(0.0, 1.0);
    final y = (0.5 + d.dy * gainY).clamp(0.0, 1.0);
    point = Offset(x * screenSize.width, y * screenSize.height);
  }

  /// Melyik gombot nézi: a már nézett gomb nagyobb területen ragad; ha a
  /// pont egyiken sincs, a legközelebbit veszi [magnetRadius]-on belül.
  GazeTargetHandle? _hitTest(Offset? p) {
    if (p == null) return null;
    bool usable(GazeTargetHandle t) => t.isOnTopRoute && t.enabled;

    final sticky = _hovered;
    if (sticky != null && usable(sticky)) {
      final r = sticky.globalRect;
      if (r != null && r.inflate(stickyMargin).contains(p)) return sticky;
    }

    GazeTargetHandle? nearest;
    var nearestDist = magnetRadius;
    for (final t in _targets) {
      if (!usable(t)) continue;
      final r = t.globalRect;
      if (r == null) continue;
      if (r.contains(p)) return t;
      final dx = math.max(0.0, math.max(r.left - p.dx, p.dx - r.right));
      final dy = math.max(0.0, math.max(r.top - p.dy, p.dy - r.bottom));
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < nearestDist) {
        nearest = t;
        nearestDist = d;
      }
    }
    return nearest;
  }

  void _decayAll(double dt, {required GazeTargetHandle? except}) {
    final step = dt * 1e6 / decay.inMicroseconds;
    for (final t in _targets) {
      if (identical(t, except) || t.progress.value == 0) continue;
      t.progress.value = (t.progress.value - step).clamp(0.0, 1.0);
    }
  }

  static double _median(Iterable<double> values) {
    final v = values.toList()..sort();
    final m = v.length ~/ 2;
    return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
  }

  @override
  void dispose() {
    camera.removeListener(_onCamera);
    camera.gazeWantsFace = false;
    super.dispose();
  }
}

/// One Euro szűrő egy értékre: ha a fej áll, erősen simít (nem remeg a
/// pötty), ha mozdul, alig késik.
class _OneEuro {
  static const double minCutoff = 0.8;
  static const double beta = 6.0;
  static const double dCutoff = 1.0;

  double? _x, _dx, _t;

  void reset() => _x = _dx = _t = null;

  double filter(double x, double t) {
    final px = _x, pt = _t;
    _t = t;
    if (px == null || pt == null || t <= pt) {
      _x = x;
      _dx = 0;
      return x;
    }
    final dt = t - pt;
    final ad = _alpha(dCutoff, dt);
    final dx = ad * ((x - px) / dt) + (1 - ad) * (_dx ?? 0);
    _dx = dx;
    final a = _alpha(minCutoff + beta * dx.abs(), dt);
    return _x = a * x + (1 - a) * px;
  }

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }
}

/// Amit a [GazeController] egy célpontról tudni akar.
abstract class GazeTargetHandle {
  /// A célpont helye a képernyőn (null, ha épp nincs kirajzolva).
  Rect? get globalRect;

  /// A legfelső oldalon van-e (az alatta lévő oldalak gombjai nem
  /// választhatók).
  bool get isOnTopRoute;

  bool get enabled;

  /// 0–1: mennyire „töltődött fel" a nézéssel.
  ValueNotifier<double> get progress;

  void onSelect();
}

class GazeScope extends InheritedWidget {
  const GazeScope({super.key, required this.controller, required super.child});

  final GazeController controller;

  static GazeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GazeScope>()!.controller;

  @override
  bool updateShouldNotify(GazeScope old) => old.controller != controller;
}
