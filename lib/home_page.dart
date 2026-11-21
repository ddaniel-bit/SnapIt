import 'package:flutter/material.dart';

import 'game/picture_mode_page.dart';
import 'game/play_page.dart';
import 'game/target_pose.dart';
import 'gaze/gaze_target.dart';
import 'pose/pose_camera.dart';
import 'ui/app_theme.dart';
import 'ui/glass.dart';
import 'ui/glass_text.dart';

/// Főoldal: elsötétített élő kép a csontvázzal, középen a logó és a
/// „Snap It!" felirat, alatta a Play és a Picture mode gomb, mellette/alatta
/// a játékosszám- és a pózmód-választó. Fekvő helyzetben két oszlopban.
///
/// Induláskor (egyszer): a fix háttér előtt középen beúszik a logó, balra
/// csúszik, mellette megjelenik a felirat, aztán az egész felcsúszik a
/// helyére, és vele jön fel a többi elem is.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  int _players = 1;
  BodyMode _mode = BodyMode.upper;

  late final AnimationController _intro =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2800),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed) setState(() {});
      });

  // Az intró szakaszai.
  late final Animation<double> _appear = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.25, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.30, 0.55, curve: Curves.easeInOutCubic),
  );
  late final Animation<double> _rise = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.62, 0.95, curve: Curves.easeInOutCubic),
  );

  final GlobalKey _brandKey = GlobalKey();

  /// A márka (logó + felirat) végleges közepétől a képernyő közepéig.
  /// (A sor középre igazított, így a közepe a felirat kibomlása közben sem
  /// mozdul.)
  Offset? _brandToCenter;

  bool get _introDone => _intro.isCompleted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIntro());
  }

  /// Megméri, hol lesz a márka a végén, és elindítja az intrót.
  void _startIntro() {
    if (!mounted) return;
    final brand = _brandKey.currentContext?.findRenderObject() as RenderBox?;
    if (brand == null || !brand.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startIntro());
      return;
    }
    final screen = MediaQuery.sizeOf(context);
    final centre = brand.localToGlobal(brand.size.center(Offset.zero));
    setState(() => _brandToCenter = screen.center(Offset.zero) - centre);
    _intro.forward();
  }

  static const double _brandGap = 14;

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// A kamera csak annyi embert kövessen, ahány játékos van.
  void _setPlayers(int n) {
    setState(() => _players = n);
    PoseCameraScope.of(context).maxPeople = n;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    PoseCameraScope.of(context).maxPeople = _players;
  }

  void _play() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => PlayPage(players: _players)));

  void _openPictureMode() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PictureModePage(players: _players, mode: _mode),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final error = PoseCameraScope.of(context).error;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final logoSize = landscape ? 58.0 : 70.0;
    final brand = AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        final toCentre = _brandToCenter;
        final rise = _rise.value;
        return Opacity(
          opacity: toCentre == null ? 0 : 1,
          child: Transform.translate(
            offset: (toCentre ?? Offset.zero) * (1 - rise),
            // A felirat a logó mögül „húzódik ki": balról jobbra bomlik ki,
            // a bal széle mindig a logó jobb széléhez simul. A sor középre
            // igazított, így ahogy szélesedik, a logó magától balra csúszik –
            // a kettő sosem fedi egymást.
            child: Row(
              key: _brandKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _appear.value,
                  child: Transform.scale(
                    scale: 0.8 + 0.2 * _appear.value,
                    child: Image.asset(
                      'media/snapit_logo.png',
                      width: logoSize,
                      height: logoSize,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                SizedBox(width: _brandGap * _reveal.value),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _reveal.value,
                    child: Opacity(
                      opacity: _reveal.value.clamp(0.0, 1.0),
                      child: Padding(
                        // Hely a betűk árnyékának, hogy ne vágja le.
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: GlassText(
                          'Snap It!',
                          fontSize: landscape ? 40 : 46,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    final subtitle = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Tap – or look at an option to select it',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error, style: const TextStyle(color: AppColors.bad)),
        ],
      ],
    );

    /// A többi elem az intró végén a márkával együtt jön fel.
    Widget risesIn(Widget child) => AnimatedBuilder(
      animation: _rise,
      builder: (context, child) => IgnorePointer(
        ignoring: !_introDone,
        child: Opacity(
          opacity: _rise.value,
          child: Transform.translate(
            offset: Offset(0, 60 * (1 - _rise.value)),
            child: child,
          ),
        ),
      ),
      child: child,
    );

    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GazeTarget(
          radius: 29,
          enabled: _introDone,
          onSelect: _play,
          child: GlassButton(
            label: 'Play',
            symbol: 'play.fill',
            tint: AppColors.accent,
            onTap: _play,
          ),
        ),
        const SizedBox(height: 14),
        GazeTarget(
          radius: 29,
          enabled: _introDone,
          onSelect: _openPictureMode,
          child: GlassButton(
            label: 'Picture mode',
            symbol: 'camera.fill',
            prominent: false,
            onTap: _openPictureMode,
          ),
        ),
      ],
    );

    final settings = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Label(Icons.groups_rounded, 'Players'),
        const SizedBox(height: 10),
        GazeSegmented(
          enabled: _introDone,
          labels: const ['1', '2', '3', '4', '5', '6'],
          index: _players - 1,
          onChanged: (i) => _setPlayers(i + 1),
        ),
        const SizedBox(height: 18),
        const _Label(Icons.accessibility_new_rounded, 'Poses'),
        const SizedBox(height: 10),
        GazeSegmented(
          enabled: _introDone,
          labels: [for (final m in BodyMode.values) m.label],
          index: _mode.index,
          onChanged: (i) => setState(() => _mode = BodyMode.values[i]),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const PoseCameraBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: landscape
                  ? Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              brand,
                              const SizedBox(height: 8),
                              risesIn(subtitle),
                              const SizedBox(height: 22),
                              risesIn(buttons),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(child: Center(child: risesIn(settings))),
                      ],
                    )
                  : Column(
                      children: [
                        const Spacer(flex: 3),
                        brand,
                        const SizedBox(height: 10),
                        risesIn(subtitle),
                        const SizedBox(height: 32),
                        risesIn(buttons),
                        const Spacer(flex: 2),
                        risesIn(settings),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: 0.8);
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
