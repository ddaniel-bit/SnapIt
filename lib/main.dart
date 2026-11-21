import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gaze/gaze_controller.dart';
import 'gaze/gaze_cursor.dart';
import 'home_page.dart';
import 'pose/pose_camera.dart';
import 'standup_reminder.dart';
import 'ui/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const SnapItApp());
}

class SnapItApp extends StatefulWidget {
  const SnapItApp({super.key});

  @override
  State<SnapItApp> createState() => _SnapItAppState();
}

class _SnapItAppState extends State<SnapItApp> {
  // Egy kamera az egész appnak – a képernyők ezt figyelik.
  final PoseCamera _camera = PoseCamera()..start();

  // Nézéses navigáció ugyanazzal a kamerával.
  late final GazeController _gaze = GazeController(_camera);

  final GlobalKey<NavigatorState> _navigator = GlobalKey();

  /// „Állj fel!" értesítés, ha sokáig nem vagy az appban – koppintásra az
  /// app a főoldalon nyílik meg (ott választod ki, hány játékos van).
  late final StandUpReminder _reminder = StandUpReminder(
    onOpenHome: () =>
        _navigator.currentState?.popUntil((route) => route.isFirst),
  );

  @override
  void initState() {
    super.initState();
    _reminder; // létrehozás: figyeli, mikor lépsz ki az appból
  }

  @override
  void dispose() {
    _reminder.dispose();
    _gaze.dispose();
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PoseCameraScope(
      camera: _camera,
      child: GazeScope(
        controller: _gaze,
        child: MaterialApp(
          navigatorKey: _navigator,
          builder: (context, child) => Stack(
            children: [
              child!,
              GazeCursorLayer(controller: _gaze),
            ],
          ),
          title: 'Snap It!',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            colorSchemeSeed: AppColors.accent,
          ),
          home: const HomePage(),
        ),
      ),
    );
  }
}
