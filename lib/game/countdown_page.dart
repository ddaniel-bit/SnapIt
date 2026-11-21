import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';

import 'package:flutter/material.dart';

import '../gaze/gaze_target.dart';
import '../pose/pose_camera.dart';
import '../ui/app_theme.dart';
import '../ui/glass.dart';
import 'expression.dart';
import 'game_widgets.dart';
import 'hand_shape.dart';
import 'pose_scorer.dart';
import 'snapshot.dart';
import 'target_pose.dart';

/// 10-től visszaszámol, közben mutatja a célpózt pálcikaemberként (játékosonként
/// egyet) és az élő pontosságot. Nullánál rögzíti az eredményt.
///
/// A játékosokat a képen balról jobbra párosítjuk a pálcikaemberekhez.
class CountdownPage extends StatefulWidget {
  const CountdownPage({super.key, required this.poses, this.nextPoses});

  /// Játékosonként a saját póz (balról jobbra P1, P2, …).
  final List<TargetPose> poses;

  /// A következő kör pózai (a „Next" gombhoz); ha nincs, nincs Next.
  final List<TargetPose> Function()? nextPoses;

  int get players => poses.length;
  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

class _CountdownPageState extends State<CountdownPage>
    with SingleTickerProviderStateMixin {
  static const int _seconds = 10;
  static const PoseScorer _scorer = PoseScorer();

  PoseCamera? _camera;
  Timer? _timer;
  int _left = _seconds;

  /// Ennyi ideig látszik a póz fotója nagyban, mielőtt a sarokba húzódik.
  static const Duration _showPhotoFor = Duration(milliseconds: 2800);

  /// A fotó összemenése a sarokba (0: nagyban középen, 1: kicsiben a sarokban).
  late final AnimationController _shrink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  Timer? _introTimer;

  /// A jelenlegi kör pózai (a „Next" lecseréli őket).
  late List<TargetPose> _poses = widget.poses;

  /// Játékosonként a simított élő pontosság (null: nem látszik).
  late List<double?> _acc = List.filled(widget.players, null);
  late List<PoseScore?> _scores = List.filled(widget.players, null);

  /// Az utolsó másodperc értékei játékosonként – ezek átlaga az eredmény.
  late List<List<double>> _lastSecond = List.generate(
    widget.players,
    (_) => [],
  );
  List<double>? _results;

  /// A fotó: az utolsó másodperc legjobb pillanata.
  CameraImage? _snapFrame;
  double _snapScore = -1;
  ui.Image? _photo;
  _SaveState _save = _SaveState.idle;

  int get _visible => _acc.where((a) => a != null).length;

  /// Az összesített pontosság: a hiányzó játékos 0-nak számít.
  double? get _total => _visible == 0
      ? null
      : _acc.fold<double>(0, (s, a) => s + (a ?? 0)) / widget.players;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cam = PoseCameraScope.of(context);
    if (!identical(cam, _camera)) {
      _camera?.removeListener(_onFrame);
      _camera
        ?..gameWantsFace = false
        ..gameWantsHands = false;
      // Az arckifejezéshez és az ujjtartáshoz a játék alatt az arcok és a
      // kezek is kellenek.
      _camera = cam
        ..addListener(_onFrame)
        ..gameWantsFace = true
        ..gameWantsHands = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _playIntro();
  }

  /// Előbb a póz fotója nagyban, aztán a sarokba húzódik, és indul a
  /// visszaszámlálás.
  void _playIntro() {
    _introTimer?.cancel();
    _shrink.value = 0;
    _introTimer = Timer(_showPhotoFor, () {
      if (!mounted) return;
      _shrink.forward().whenComplete(() {
        if (mounted) _startTimer();
      });
    });
  }

  /// Következő kör: új pózok, és újra a bemutatás nagy fotóval.
  void _next() {
    final next = widget.nextPoses?.call();
    if (next == null) return;
    _timer?.cancel();
    _resetRound();
    setState(() => _poses = next);
    _playIntro();
  }

  void _restart() {
    _resetRound();
    _startTimer();
  }

  void _resetRound() {
    setState(() {
      _left = _seconds;
      _results = null;
      _acc = List.filled(widget.players, null);
      _scores = List.filled(widget.players, null);
      _lastSecond = List.generate(widget.players, (_) => []);
      _snapFrame = null;
      _snapScore = -1;
      _photo = null;
      _save = _SaveState.idle;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        setState(() {
          _left = 0;
          _results = [
            for (final l in _lastSecond)
              l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length,
          ];
        });
        _developPhoto();
        return;
      }
      setState(() => _left--);
    });
  }

  void _onFrame() {
    final cam = _camera;
    if (cam == null || _results != null || !mounted) return;
    final people = cam.people; // balról jobbra
    setState(() {
      for (var i = 0; i < widget.players; i++) {
        final s = i < people.length
            ? _scorer.score(
                people[i].frame,
                _poses[i],
                mirror: cam.mirror,
                face: faceForBody(people[i].frame, cam.faces)?.metrics,
                hands: cam.hands,
              )
            : null;
        if (s == null) {
          _acc[i] = null;
          _scores[i] = null;
        } else {
          final prev = _acc[i];
          _acc[i] = prev == null ? s.accuracy : prev * 0.7 + s.accuracy * 0.3;
          _scores[i] = s;
        }
        if (_left <= 1) _lastSecond[i].add(_acc[i] ?? 0);
      }
      // Az utolsó másodpercben a legjobb pillanat lesz a fotó.
      final total = _total ?? 0;
      if (_left <= 1 && cam.lastImage != null && total >= _snapScore) {
        _snapScore = total;
        _snapFrame = cam.lastImage;
      }
    });
  }

  /// A rögzített képkockából kép (ha nem volt jó pillanat, az utolsó kocka).
  Future<void> _developPhoto() async {
    final frame = _snapFrame ?? _camera?.lastImage;
    if (frame == null) return;
    final results = _results;
    if (results == null) return;
    final total = results.reduce((a, b) => a + b) / results.length;
    final image = await stampPhoto(
      await imageFromCamera(frame),
      accuracy: total,
      team: widget.players > 1,
    );
    if (!mounted || _results == null) return;
    setState(() => _photo = image);
  }

  Future<void> _savePhoto() async {
    final photo = _photo;
    if (photo == null || _save != _SaveState.idle) return;
    setState(() => _save = _SaveState.saving);
    final ok = await saveToPhotos(photo);
    if (!mounted) return;
    setState(() => _save = ok ? _SaveState.saved : _SaveState.idle);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save – allow Photos access in Settings'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _introTimer?.cancel();
    _shrink.dispose();
    _camera
      ?..removeListener(_onFrame)
      ..gameWantsFace = false
      ..gameWantsHands = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PoseCameraBackground(dim: results == null ? 0.25 : 0.72),
          SafeArea(
            child: results == null ? _buildCountdown() : _buildResult(results),
          ),
          // Vaku-villanás, amikor elkészül a fotó.
          if (results != null)
            IgnorePointer(
              child: TweenAnimationBuilder<double>(
                key: ObjectKey(results),
                tween: Tween(begin: 1, end: 0),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                builder: (context, v, _) =>
                    ColoredBox(color: Colors.white.withValues(alpha: 0.85 * v)),
              ),
            ),
        ],
      ),
    );
  }

  void _done() => Navigator.of(context).popUntil((route) => route.isFirst);

  bool get _landscape =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  Widget _topBar() => Row(
    children: [
      GlassIconButton(
        symbol: 'xmark',
        onTap: () => Navigator.of(context).pop(),
      ),
      const Spacer(),
      Icon(_first.category.icon, color: Colors.white70, size: 18),
      const SizedBox(width: 6),
      Text(
        '${_first.category.label} · ${_first.mode.label}',
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(width: 8),
    ],
  );

  TargetPose get _first => _poses.first;

  /// Mindenki ugyanazt a pózt kapta-e (pl. egy játékos).
  bool get _samePose => _poses.toSet().length == 1;

  /// A kért arckifejezés és kéztartás(ok) röviden (emojikkal).
  static String _requirementText(TargetPose p, {bool labels = true}) => [
    labels ? '${p.expression.emoji} ${p.expression.label}' : p.expression.emoji,
    for (final h in {p.lHand, p.rHand})
      if (h != HandShape.any) labels ? '${h.emoji} ${h.label}' : h.emoji,
  ].join(labels ? '   ' : ' ');

  /// A kért arckifejezés és kéztartás(ok) egy címkén.
  Widget _requirements(TargetPose p) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      _requirementText(p),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  /// A pálcikaemberek kicsiben, visszajelzésnek (zöldülnek, ami stimmel).
  /// Ha a játékosok más-más pózt kaptak, mindegyik alatt ott a póz neve és
  /// a kért arc/kéz.
  Widget _figures(double maxWidth) {
    final n = widget.players;
    final size = n == 1 ? 100.0 : ((maxWidth - 16) / n).clamp(44.0, 84.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < n; i++)
          SizedBox(
            width: size,
            child: PlayerFigure(
              pose: _poses[i],
              label: n == 1 ? null : 'P${i + 1}',
              accuracy: n == 1 ? null : _acc[i],
              score: _scores[i],
              caption: _samePose
                  ? null
                  : '${_poses[i].name}\n'
                        '${_requirementText(_poses[i], labels: false)}',
            ),
          ),
      ],
    );
  }

  /// A fotók helye: nagyban (bemutatáskor) és kicsiben a jobb felső sarokban.
  /// [k] fotó egy vagy két sorban.
  (List<Rect>, List<Rect>) _photoRects(
    BoxConstraints box,
    int k,
    bool landscape,
  ) {
    final cols = k <= 3 ? k : 3;
    final rows = (k / cols).ceil();
    const gap = 10.0;

    final availW = landscape ? box.maxWidth * 0.58 : box.maxWidth * 0.94;
    final availH = landscape ? box.maxHeight * 0.78 : box.maxHeight * 0.56;
    final bigSide = [
      (availW - gap * (cols - 1)) / cols,
      (availH - gap * (rows - 1) - (k > 1 ? 22.0 * rows : 0)) / rows,
    ].reduce((a, b) => a < b ? a : b);
    final gridW = cols * bigSide + (cols - 1) * gap;
    final left0 = landscape
        ? box.maxWidth * 0.3 - gridW / 2
        : (box.maxWidth - gridW) / 2;
    final gridH = rows * bigSide + (rows - 1) * (gap + (k > 1 ? 22 : 0));
    final top0 = landscape ? (box.maxHeight - gridH) / 2 : box.maxHeight * 0.03;

    final smallSide = k == 1
        ? (landscape ? 92.0 : 108.0)
        : (landscape ? 56.0 : 62.0);
    const smallGap = 6.0;

    final big = <Rect>[], small = <Rect>[];
    for (var i = 0; i < k; i++) {
      final c = i % cols, r = i ~/ cols;
      big.add(
        Rect.fromLTWH(
          left0 + c * (bigSide + gap),
          top0 + r * (bigSide + gap + (k > 1 ? 22 : 0)),
          bigSide,
          bigSide,
        ),
      );
      // Kicsiben jobbra igazítva, az utolsó a sarokban.
      final fromRight = (cols - 1 - c);
      small.add(
        Rect.fromLTWH(
          box.maxWidth - smallSide - fromRight * (smallSide + smallGap),
          r * (smallSide + smallGap),
          smallSide,
          smallSide,
        ),
      );
    }
    return (big, small);
  }

  Widget _counter() => AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    transitionBuilder: (child, anim) => ScaleTransition(
      scale: Tween(begin: 1.6, end: 1.0).animate(anim),
      child: FadeTransition(opacity: anim, child: child),
    ),
    child: Text(
      '$_left',
      key: ValueKey(_left),
      style: TextStyle(
        color: _left <= 3 ? AppColors.accentLight : Colors.white,
        fontSize: 110,
        fontWeight: FontWeight.w900,
        height: 1,
        shadows: const [Shadow(color: Colors.black87, blurRadius: 20)],
      ),
    ),
  );

  Widget _buildCountdown() {
    final pill = AccuracyPill(
      accuracy: _total,
      missing: widget.players - _visible,
    );
    final same = _samePose;
    // Egy közös póznál egy fotó és egy névcímke; különböző pózoknál
    // játékosonként egy-egy fotó.
    final shown = same ? [_first] : _poses;
    final name = GlassLabel(text: _first.name, symbol: 'figure.dance');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          _topBar(),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => AnimatedBuilder(
                animation: _shrink,
                builder: (context, _) {
                  final t = Curves.easeInOutCubic.transform(_shrink.value);
                  final landscape = _landscape;
                  final (big, small) = _photoRects(
                    box,
                    shown.length,
                    landscape,
                  );
                  final bigBottom = big
                      .map((r) => r.bottom)
                      .reduce((a, b) => a > b ? a : b);

                  // Visszajelzés: (név, kért arc/kéz,) pálcikaember(ek), accuracy.
                  final header = [
                    if (same && t > 0) name,
                    if (same) ...[
                      const SizedBox(height: 6),
                      _requirements(_first),
                    ],
                  ];
                  final feedback = landscape
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _figures(box.maxWidth * 0.5),
                            const SizedBox(width: 16),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ...header,
                                const SizedBox(height: 8),
                                pill,
                              ],
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...header,
                            const SizedBox(height: 8),
                            _figures(box.maxWidth),
                            const SizedBox(height: 8),
                            pill,
                          ],
                        );

                  return Stack(
                    children: [
                      // A visszaszámlálás és alul a visszajelzés – a fotó
                      // összemenésével együtt jelennek meg.
                      Opacity(
                        opacity: t,
                        child: Column(
                          children: [
                            Expanded(child: Center(child: _counter())),
                            feedback,
                          ],
                        ),
                      ),
                      // Bemutatáskor: több pózánál minden fotó alatt, kinek
                      // melyik jutott.
                      if (t < 1 && !same)
                        for (var i = 0; i < shown.length; i++)
                          Positioned(
                            left: big[i].left - 20,
                            width: big[i].width + 40,
                            top: big[i].bottom + 3,
                            child: Opacity(
                              opacity: 1 - t,
                              child: Text(
                                'P${i + 1} · ${shown[i].name}',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      // Bemutatáskor a fotó(k) alatt: név, leírás, kért arc/kéz.
                      if (t < 1)
                        Positioned(
                          left: landscape ? box.maxWidth * 0.6 : 0,
                          right: 0,
                          top: landscape ? 0 : bigBottom + (same ? 12 : 30),
                          bottom: landscape ? 0 : null,
                          child: Opacity(
                            opacity: 1 - t,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (same) ...[
                                  name,
                                  const SizedBox(height: 10),
                                  Text(
                                    _first.hint,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontSize: 16,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _requirements(_first),
                                  const SizedBox(height: 12),
                                ] else ...[
                                  const Text(
                                    'Everyone gets their own pose!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                const Text(
                                  'Get ready…',
                                  style: TextStyle(
                                    color: AppColors.accentLight,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      for (var i = 0; i < shown.length; i++)
                        Positioned.fromRect(
                          rect: Rect.lerp(big[i], small[i], t)!,
                          child: ReferencePhoto(
                            pose: shown[i],
                            radius: 26 - 12 * t,
                            badge: same ? null : 'P${i + 1}',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(List<double> results) {
    final n = widget.players;
    final total = results.reduce((a, b) => a + b) / n;
    final color = AppColors.forAccuracy(total);
    final verdict = total >= 90
        ? 'Perfect!'
        : total >= 75
        ? 'Great job!'
        : total >= 45
        ? 'Not bad!'
        : 'Keep trying!';

    // A fotó nagyban – az accuracy és a vízjel már rajta van. Fent az
    // értékelés, több játékosnál a játékosonkénti százalékok.
    final photo = _PhotoCard(
      image: _photo,
      overlay: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _VerdictChip(verdict, color),
          if (n > 1)
            for (var i = 0; i < n; i++) _ScoreChip('P${i + 1}', results[i]),
        ],
      ),
    );

    final saveButton = GazeTarget(
      radius: 29,
      enabled: _photo != null && _save == _SaveState.idle,
      onSelect: _savePhoto,
      child: GlassButton(
        label: switch (_save) {
          _SaveState.idle => 'Save',
          _SaveState.saving => 'Saving…',
          _SaveState.saved => 'Saved',
        },
        symbol: _save == _SaveState.saved
            ? 'checkmark.circle.fill'
            : 'square.and.arrow.down',
        tint: _save == _SaveState.saved ? AppColors.good : AppColors.accent,
        onTap: _photo != null && _save == _SaveState.idle ? _savePhoto : null,
      ),
    );
    final again = GazeTarget(
      radius: 29,
      onSelect: _restart,
      child: GlassButton(
        label: 'Try again',
        symbol: 'arrow.counterclockwise',
        prominent: false,
        fontSize: 17,
        onTap: _restart,
      ),
    );
    final next = widget.nextPoses == null
        ? null
        : GazeTarget(
            radius: 29,
            onSelect: _next,
            child: GlassButton(
              label: 'Next',
              symbol: 'forward.fill',
              tint: AppColors.accent,
              onTap: _next,
            ),
          );
    final done = GazeTarget(
      radius: 29,
      onSelect: _done,
      child: GlassButton(
        label: 'Done',
        symbol: 'checkmark',
        prominent: false,
        fontSize: 17,
        onTap: _done,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: _landscape
          ? Row(
              children: [
                Expanded(child: photo),
                const SizedBox(width: 20),
                SizedBox(
                  width: 260,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      saveButton,
                      if (next != null) ...[const SizedBox(height: 12), next],
                      const SizedBox(height: 12),
                      again,
                      const SizedBox(height: 12),
                      done,
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(child: photo),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: saveButton),
                    if (next != null) ...[
                      const SizedBox(width: 12),
                      Expanded(child: next),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: again),
                    const SizedBox(width: 12),
                    Expanded(child: done),
                  ],
                ),
              ],
            ),
    );
  }
}

enum _SaveState { idle, saving, saved }

/// A fotó nagyban, lekerekítve, a tetején az [overlay]-jel. Amíg a kép
/// készül, egy töltés-jelző látszik.
class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.image, required this.overlay});

  final ui.Image? image;
  final Widget overlay;

  @override
  Widget build(BuildContext context) {
    final img = image;
    final aspect = img == null ? 3 / 4 : img.width / img.height;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (img == null)
                const Center(child: CircularProgressIndicator())
              else
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 1.04 - 0.04 * t,
                      child: child,
                    ),
                  ),
                  child: RawImage(image: img, fit: BoxFit.cover),
                ),
              Positioned(left: 14, top: 14, right: 14, child: overlay),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip(this.label, this.accuracy);

  final String label;
  final double accuracy;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forAccuracy(accuracy);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        '$label  ${accuracy.round()}%',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
