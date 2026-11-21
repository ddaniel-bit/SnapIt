import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'game/meme_poses.dart';

/// „Állj fel!" emlékeztető: ha a játékos kilép az appból, és egy ideig nem
/// jön vissza, helyi értesítést kap, hogy álljon fel, és csináljon meg egy
/// pózt. Koppintásra az app a főoldalon nyílik meg ([onOpenHome]) – ott lehet
/// kiválasztani, hány játékos van, és indítani a játékot.
/// Natív oldal: `StandUpReminder` az AppDelegate-ben.
class StandUpReminder {
  StandUpReminder({required this.onOpenHome}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openHome') onOpenHome();
    });
    _lifecycle = AppLifecycleListener(onHide: _schedule, onShow: _cancel);
  }

  /// Ennyi idővel azután jön az értesítés, hogy kiléptél az appból.
  static const Duration delay = Duration(seconds: 30);

  static const MethodChannel _channel = MethodChannel('projekt/standup');

  final VoidCallback onOpenHome;
  late final AppLifecycleListener _lifecycle;

  void _schedule() {
    final meme = kMemePoses[math.Random().nextInt(kMemePoses.length)];
    _channel.invokeMethod<void>('schedule', {
      'seconds': delay.inSeconds,
      'title': 'Time to stand up! 🧍',
      'body':
          "You've been sitting for way too long. Get up and strike a pose – "
          'can you nail the ${meme.name}? 📸',
    });
  }

  void _cancel() => _channel.invokeMethod<void>('cancel');

  void dispose() => _lifecycle.dispose();
}
