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
import 'meme_poses.dart';
import 'play_rules.dart';
import 'pose_scorer.dart';
import 'snapshot.dart';
import 'target_pose.dart';

enum _Phase { intro, posing, judged, gameOver }

/// A játékmód: egymás után jönnek a mémek, mindegyiket le kell utánozni.
/// A mém 1,5 mp-ig nagyban látszik, aztán a sarokba megy, és indul az idő –
/// ami körről körre rövidül, miközben a minimum pontosság nő. Minden körben
/// annyi pont jár, ahány százalékos lett a póz; ha a minimum alatt maradsz,
/// kiestél. A végén a legjobb pillanatod fotóját a pontszámmal meg lehet
/// osztani: „Beat me if you can!".
class PlayPage extends StatefulWidget {
  const PlayPage({super.key, required this.players});

  final int players;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage>
    with SingleTickerProviderStateMixin {
  static const PoseScorer _scorer = PoseScorer();

  /// A kör végén ennyi ideig látszik az eredmény.
  static const Duration _judgeFor = Duration(milliseconds: 1100);

  /// A kör utolsó ennyi másodpercének átlaga számít.
  static const double _judgeWindow = 0.6;

  /// A munkamenet legjobb pontszáma.
  static int _best = 0;

  final MemeDeck _deck = MemeDeck(List.of(kMemePoses));
  PoseCamera? _camera;

  late final AnimationController _shrink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  _Phase _phase = _Phase.intro;
  int _round = 0;
  late TargetPose _pose;

  Timer? _timer;
  double _total = 0; // a kör ideje (s)
  double _left = 0; // hátralévő idő (s)

  int get _n => widget.players;
  bool get _versus => _n > 1;

  /// Játékosonként (P1, P2, …): pontszám, kiesett-e, élő pontosság,
  /// az utolsó kör eredménye és a kör végi mérőablak.
  late List<int> _points = List.filled(_n, 0);
  late List<bool> _out = List.filled(_n, false);
  late List<double?> _acc = List.filled(_n, null);
  late List<PoseScore?> _scores = List.filled(_n, null);
  late List<double?> _lastResults = List.filled(_n, null);
  late List<List<double>> _windows = List.generate(_n, (_) => []);

  /// Melyik követett ember melyik játékos (helycserénél sem keveredik).
  late final PlayerSlots _slots = PlayerSlots(_n);

  /// Hányadik körben esett ki (a ranglistához).
  late List<int> _outRound = List.filled(_n, 0);

  // A legjobb pillanat (a megosztáshoz).
  double _bestFrameScore = -1;
  CameraImage? _bestFrame;
  TargetPose? _bestPose;
  ui.Image? _shareImage;

  Iterable<int> get _alive => [
    for (var i = 0; i < _n; i++)
      if (!_out[i]) i,
  ];

  /// Egyedül: az élő pontosság (versenyben a pálcikaemberek alatt látszik).
  double? get _soloAccuracy => _acc.first;

  double get _need => PlayRules.minAccuracyFor(_round);

  /// A nyertes(ek): a legtöbb pontot gyűjtő játékos(ok).
  List<int> get _winners {
    final top = _points.reduce((a, b) => a > b ? a : b);
    return [
      for (var i = 0; i < _n; i++)
        if (_points[i] == top) i,
    ];
  }

  int get _topScore => _points.reduce((a, b) => a > b ? a : b);

  @override
  void initState() {
    super.initState();
    _nextRound();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cam = PoseCameraScope.of(context);
    if (!identical(cam, _camera)) {
      _camera
        ?..removeListener(_onFrame)
        ..gameWantsFace = false
        ..gameWantsHands = false;
      _camera = cam
        ..addListener(_onFrame)
        ..gameWantsFace = true
        ..gameWantsHands = true;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shrink.dispose();
    _camera
      ?..removeListener(_onFrame)
      ..gameWantsFace = false
      ..gameWantsHands = false;
    super.dispose();
  }

  // ── A játék menete ──

  void _nextRound() {
    _timer?.cancel();
    setState(() {
      _round++;
      _pose = _deck.next();
      _phase = _Phase.intro;
      _total = PlayRules.secondsFor(_round);
      _left = _total;
      for (final w in _windows) {
        w.clear();
      }
      _lastResults = List.filled(_n, null);
    });
    _shrink.value = 0;
    _timer = Timer(PlayRules.showMemeFor, () {
      if (!mounted) return;
      _shrink.forward().whenComplete(() {
        if (mounted) _startPosing();
      });
    });
  }

  void _startPosing() {
    setState(() => _phase = _Phase.posing);
    final start = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(start).inMicroseconds / 1e6;
      setState(() => _left = (_total - elapsed).clamp(0.0, _total));
      if (_left <= 0) {
        t.cancel();
        _judge();
      }
    });
  }

  /// A kör vége: minden még játékban lévő játékos annyi pontot kap, ahány
  /// százalék lett – aki a minimum alatt maradt, kiesik.
  void _judge() {
    setState(() {
      for (final i in _alive.toList()) {
        final w = _windows[i];
        final result = w.isEmpty
            ? (_acc[i] ?? 0)
            : w.reduce((a, b) => a + b) / w.length;
        _lastResults[i] = result;
        if (result >= _need) {
          _points[i] += result.round();
        } else {
          _out[i] = true;
          _outRound[i] = _round;
        }
      }
      _phase = _Phase.judged;
    });
    _timer = Timer(_judgeFor, () {
      if (!mounted) return;
      if (_alive.isNotEmpty) {
        _nextRound();
      } else {
        _gameOver();
      }
    });
  }

  Future<void> _gameOver() async {
    if (_topScore > _best) _best = _topScore;
    setState(() => _phase = _Phase.gameOver);
    final frame = _bestFrame ?? _camera?.lastImage;
    if (frame == null) return;
    final image = await composeShareImage(
      await imageFromCamera(frame),
      score: _topScore,
      memeAsset: (_bestPose ?? _pose).photo,
    );
    if (mounted) setState(() => _shareImage = image);
  }

  void _playAgain() {
    _slots.reset();
    setState(() {
      _round = 0;
      _points = List.filled(_n, 0);
      _out = List.filled(_n, false);
      _outRound = List.filled(_n, 0);
      _acc = List.filled(_n, null);
      _scores = List.filled(_n, null);
      _windows = List.generate(_n, (_) => []);
      _bestFrameScore = -1;
      _bestFrame = null;
      _bestPose = null;
      _shareImage = null;
    });
    _nextRound();
  }

  Future<void> _share() async {
    final image = _shareImage;
    if (image == null) return;
    final text = _versus
        ? '${_winnerText()} with $_topScore points in Snap It! '
              'Beat me if you can! 💪'
        : 'I scored $_topScore points in Snap It! Beat me if you can! 💪';
    await shareImage(image, text);
  }

  String _winnerText() {
    final w = _winners;
    return w.length == 1
        ? 'P${w.first + 1} wins'
        : '${w.map((i) => 'P${i + 1}').join(' & ')} tie';
  }

  void _done() => Navigator.of(context).pop();

  void _onFrame() {
    final cam = _camera;
    if (cam == null || !mounted || _phase == _Phase.gameOver) return;
    final people = cam.people;
    final bySlot = _slots.assign([
      for (final p in people) (id: p.id, x: p.center.dx),
    ]);
    setState(() {
      var bestNow = -1.0;
      for (var i = 0; i < _n; i++) {
        final idx = bySlot[i];
        final s = idx == null
            ? null
            : _scorer.score(
                people[idx].frame,
                _pose,
                mirror: cam.mirror,
                face: faceForBody(people[idx].frame, cam.faces)?.metrics,
                hands: cam.hands,
              );
        if (s == null) {
          _acc[i] = null;
          _scores[i] = null;
        } else {
          final prev = _acc[i];
          _acc[i] = prev == null ? s.accuracy : prev * 0.6 + s.accuracy * 0.4;
          _scores[i] = s;
        }
        if (_phase == _Phase.posing && !_out[i]) {
          final a = _acc[i] ?? 0;
          if (_left <= _judgeWindow) _windows[i].add(a);
          if (a > bestNow) bestNow = a;
        }
      }
      // A játék legjobb pillanata (bárkié) lesz a megosztott fotó.
      if (_phase == _Phase.posing &&
          cam.lastImage != null &&
          bestNow > _bestFrameScore) {
        _bestFrameScore = bestNow;
        _bestFrame = cam.lastImage;
        _bestPose = _pose;
      }
    });
  }

  // ── Felület ──

  bool get _landscape =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  @override
  Widget build(BuildContext context) {
    final over = _phase == _Phase.gameOver;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PoseCameraBackground(dim: over ? 0.72 : 0.25),
          SafeArea(child: over ? _buildGameOver() : _buildRound()),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color color = Colors.white}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800),
    ),
  );

  String _requirements(TargetPose p) => [
    '${p.expression.emoji} ${p.expression.label}',
    for (final h in {p.lHand, p.rHand})
      if (h != HandShape.any) '${h.emoji} ${h.label}',
  ].join('   ');

  Widget _buildRound() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              GlassIconButton(symbol: 'xmark', onTap: _done),
              const SizedBox(width: 10),
              _chip('Round $_round'),
              const Spacer(),
              _chip('$_score pts', color: AppColors.good),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => AnimatedBuilder(
                animation: _shrink,
                builder: (context, _) => _roundStage(box),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundStage(BoxConstraints box) {
    final t = Curves.easeInOutCubic.transform(_shrink.value);
    final landscape = _landscape;

    final bigSide = landscape
        ? box.maxHeight * 0.75
        : (box.maxWidth * 0.86).clamp(0.0, box.maxHeight * 0.58);
    final big = Rect.fromLTWH(
      landscape
          ? box.maxWidth * 0.3 - bigSide / 2
          : (box.maxWidth - bigSide) / 2,
      landscape ? (box.maxHeight - bigSide) / 2 : box.maxHeight * 0.03,
      bigSide,
      bigSide,
    );
    final smallSide = landscape ? 92.0 : 112.0;
    final small = Rect.fromLTWH(
      box.maxWidth - smallSide,
      0,
      smallSide,
      smallSide,
    );

    final acc = _accuracy;
    final ok = acc != null && acc >= _need;
    final figureSize = widget.players == 1
        ? 96.0
        : ((box.maxWidth * (landscape ? 0.5 : 1) - 16) / widget.players).clamp(
            44.0,
            84.0,
          );
    final figures = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.players; i++)
          SizedBox(
            width: figureSize,
            child: PlayerFigure(
              pose: _pose,
              label: widget.players == 1 ? null : 'P${i + 1}',
              accuracy: widget.players == 1 ? null : _acc[i],
              score: _scores[i],
            ),
          ),
      ],
    );
    final status = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip(
          'Need ${_need.round()}%',
          color: ok ? AppColors.good : AppColors.accentLight,
        ),
        const SizedBox(height: 8),
        AccuracyPill(accuracy: acc, missing: widget.players - _visible),
      ],
    );

    return Stack(
      children: [
        // Az idő, a minimum és a visszajelzés – a mém összemenésével jön.
        Opacity(
          opacity: t,
          child: Column(
            children: [
              // Fogyó idő-sáv.
              Padding(
                padding: EdgeInsets.only(right: small.width + 12, top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _total == 0 ? 0 : _left / _total,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(
                      _left < 1.5 ? AppColors.bad : AppColors.accentLight,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _left.toStringAsFixed(1),
                    style: TextStyle(
                      color: _left < 1.5 ? AppColors.bad : Colors.white,
                      fontSize: 96,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 20),
                      ],
                    ),
                  ),
                ),
              ),
              if (landscape)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [figures, const SizedBox(width: 16), status],
                )
              else ...[
                figures,
                const SizedBox(height: 8),
                status,
              ],
            ],
          ),
        ),
        // Bemutatáskor a mém alatt: név, leírás, kért arc/kéz.
        if (t < 1)
          Positioned(
            left: landscape ? box.maxWidth * 0.6 : 0,
            right: 0,
            top: landscape ? 0 : big.bottom + 12,
            bottom: landscape ? 0 : null,
            child: Opacity(
              opacity: 1 - t,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassLabel(text: _pose.name, symbol: 'theatermasks.fill'),
                  const SizedBox(height: 8),
                  Text(
                    _pose.hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _chip(_requirements(_pose)),
                  const SizedBox(height: 10),
                  Text(
                    'Copy this! · ${PlayRules.secondsFor(_round).toStringAsFixed(1)} s'
                    ' · need ${_need.round()}%',
                    style: const TextStyle(
                      color: AppColors.accentLight,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned.fromRect(
          rect: Rect.lerp(big, small, t)!,
          child: ReferencePhoto(pose: _pose, radius: 26 - 12 * t),
        ),
        // A kör eredménye.
        if (_phase == _Phase.judged && _lastResult != null)
          Center(child: _judgeBanner(_lastResult!)),
      ],
    );
  }

  Widget _judgeBanner(double result) {
    final passed = result >= _need;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: (passed ? AppColors.good : AppColors.bad).withValues(
              alpha: 0.8,
            ),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              passed ? '+${result.round()}' : '${result.round()}%',
              style: TextStyle(
                color: passed ? AppColors.good : AppColors.bad,
                fontSize: 64,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              passed ? 'Nice!' : 'Needed ${_need.round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOver() {
    final result = _lastResult ?? 0;
    final image = _shareImage;
    final card = Center(
      child: AspectRatio(
        aspectRatio: image == null ? 3 / 4 : image.width / image.height,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
          ),
          child: image == null
              ? const Center(child: CircularProgressIndicator())
              : RawImage(image: image, fit: BoxFit.cover),
        ),
      ),
    );
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Game over!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${result.round()}% – you needed ${_need.round()}%',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$_score pts',
          style: const TextStyle(
            color: AppColors.good,
            fontSize: 48,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_round - 1} round${_round - 1 == 1 ? '' : 's'} · best $_best pts',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 14,
          ),
        ),
      ],
    );
    final share = GazeTarget(
      radius: 29,
      enabled: image != null,
      onSelect: _share,
      child: GlassButton(
        label: 'Share',
        symbol: 'square.and.arrow.up',
        tint: AppColors.accent,
        onTap: image == null ? null : _share,
      ),
    );
    final again = GazeTarget(
      radius: 29,
      onSelect: _playAgain,
      child: GlassButton(
        label: 'Play again',
        symbol: 'arrow.counterclockwise',
        prominent: false,
        fontSize: 17,
        onTap: _playAgain,
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
                Expanded(child: card),
                const SizedBox(width: 20),
                SizedBox(
                  width: 280,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      info,
                      const SizedBox(height: 16),
                      share,
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
                info,
                const SizedBox(height: 14),
                Expanded(child: card),
                const SizedBox(height: 16),
                share,
                const SizedBox(height: 12),
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
