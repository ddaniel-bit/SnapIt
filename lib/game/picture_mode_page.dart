import 'package:flutter/material.dart';

import '../gaze/gaze_target.dart';
import '../pose/pose_camera.dart';
import '../ui/app_theme.dart';
import '../ui/glass.dart';
import 'countdown_page.dart';
import 'target_pose.dart';

/// Picture mode: kategóriaválasztó (Party, Couple, Family, Casual), majd Start.
/// Állva 2×2-es rács, fekve egy sor.
class PictureModePage extends StatefulWidget {
  const PictureModePage({super.key, required this.players, required this.mode});

  final int players;
  final BodyMode mode;

  @override
  State<PictureModePage> createState() => _PictureModePageState();
}

class _PictureModePageState extends State<PictureModePage> {
  PoseCategory? _selected;

  /// Az utoljára dobott póz kategóriánként – hogy egymás után ne ugyanaz jöjjön.
  static final Map<(PoseCategory, BodyMode), TargetPose> _lastPose = {};

  /// Játékosonként egy véletlen póz a kategóriából – párban/csoportban
  /// lehetőleg mindenki mást kap, és nem ugyanaz kezd, mint legutóbb.
  List<TargetPose> _pickPoses(PoseCategory c) {
    final key = (c, widget.mode);
    final poses = TargetPose.forPlayers(
      c,
      widget.mode,
      widget.players,
      except: _lastPose[key],
    );
    _lastPose[key] = poses.first;
    return poses;
  }

  void _start() {
    final selected = _selected;
    if (selected == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CountdownPage(
          poses: _pickPoses(selected),
          nextPoses: () => _pickPoses(selected),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final chips = [
      _Chip('${widget.players} ${widget.players == 1 ? 'player' : 'players'}'),
      _Chip(widget.mode.label),
    ];

    final header = Row(
      children: [
        GazeTarget(
          onSelect: () => Navigator.of(context).pop(),
          child: GlassIconButton(
            symbol: 'chevron.left',
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 26),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Picture mode',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (landscape)
          Row(children: [chips[0], const SizedBox(width: 6), chips[1]])
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [chips[0], const SizedBox(height: 6), chips[1]],
          ),
      ],
    );

    final cards = [
      for (final c in PoseCategory.values)
        GazeTarget(
          enabled: c != selected,
          onSelect: () => setState(() => _selected = c),
          child: _CategoryCard(
            category: c,
            selected: c == selected,
            onTap: () => setState(() => _selected = c),
          ),
        ),
    ];

    final start = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GazeTarget(
          radius: 29,
          enabled: selected != null,
          onSelect: _start,
          child: GlassButton(
            label: 'Start',
            symbol: 'play.fill',
            tint: AppColors.accent,
            onTap: selected == null ? null : _start,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          selected == null
              ? 'Pick a category first'
              : '${selected.label} · a random pose · 10 seconds',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const PoseCameraBackground(dim: 0.8),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 10),
                  Text(
                    'Choose a category',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: landscape
                        ? Row(
                            children: [
                              for (var i = 0; i < cards.length; i++) ...[
                                if (i > 0) const SizedBox(width: 12),
                                Expanded(child: cards[i]),
                              ],
                            ],
                          )
                        : GridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 1.05,
                            physics: const NeverScrollableScrollPhysics(),
                            children: cards,
                          ),
                  ),
                  const SizedBox(height: 14),
                  landscape
                      ? Center(child: SizedBox(width: 360, child: start))
                      : start,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final PoseCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      scale: selected ? 1.0 : 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        clipBehavior: Clip.antiAlias,
        decoration: selected
            ? AppColors.gradientBox(AppColors.accent)
            : BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(category.icon, color: Colors.white, size: 46),
                      const SizedBox(height: 10),
                      Text(
                        category.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
