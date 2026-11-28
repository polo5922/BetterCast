import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// True when the system asks for reduced motion.
bool reduceMotion(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// Play/pause icon that morphs between both states.
class PlayPauseIcon extends StatefulWidget {
  const PlayPauseIcon({super.key, required this.playing, this.size, this.color});
  final bool playing;
  final double? size;
  final Color? color;

  @override
  State<PlayPauseIcon> createState() => _PlayPauseIconState();
}

class _PlayPauseIconState extends State<PlayPauseIcon> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(PlayPauseIcon old) {
    super.didUpdateWidget(old);
    if (old.playing == widget.playing) return;
    if (reduceMotion(context)) {
      _c.value = widget.playing ? 1 : 0;
    } else {
      widget.playing ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedIcon(
        icon: AnimatedIcons.play_pause,
        progress: CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic),
        size: widget.size,
        color: widget.color,
      );
}

/// Marks a list whose first items fade and slide in when it first shows.
class StaggerScope extends StatefulWidget {
  const StaggerScope({super.key, required this.child});
  final Widget child;

  @override
  State<StaggerScope> createState() => _StaggerScopeState();
}

class _StaggerScopeState extends State<StaggerScope> {
  final _born = DateTime.now();

  @override
  Widget build(BuildContext context) => _StaggerClock(born: _born, child: widget.child);
}

class _StaggerClock extends InheritedWidget {
  const _StaggerClock({required this.born, required super.child});
  final DateTime born;

  @override
  bool updateShouldNotify(_StaggerClock old) => old.born != born;
}

/// One item of a [StaggerScope] list. Only items built right after the list
/// appeared are animated (not those built later while scrolling).
class Stagger extends StatefulWidget {
  const Stagger({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final clock = context.dependOnInheritedWidgetOfExactType<_StaggerClock>();
    final fresh = clock != null &&
        DateTime.now().difference(clock.born) < const Duration(milliseconds: 400) &&
        widget.index < 12;
    if (!fresh || reduceMotion(context)) return;
    final delay = 35 * widget.index;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: 320 + delay));
    _c!.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final total = c.duration!.inMilliseconds;
    final start = (35 * widget.index) / total;
    final a = CurvedAnimation(parent: c, curve: Interval(start, 1, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: a,
      child: AnimatedBuilder(
        animation: a,
        builder: (_, child) => Transform.translate(offset: Offset(0, 12 * (1 - a.value)), child: child),
        child: widget.child,
      ),
    );
  }
}

/// Fades the new tab in (with a slight zoom) when the selected tab changes.
class TabFade extends StatefulWidget {
  const TabFade({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<TabFade> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1);

  @override
  void didUpdateWidget(TabFade old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !reduceMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: widget.child),
    );
  }
}

/// Page sliding in sideways (podcast, episode pages on phones).
Page<void> sharedAxisPage(GoRouterState state, Widget child) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (context, animation, secondary, child) => reduceMotion(context)
          ? child
          : SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondary,
              transitionType: SharedAxisTransitionType.horizontal,
              child: child,
            ),
    );

/// Full player route: slides up from the bottom with a fade.
Page<void> playerPage(GoRouterState state, Widget child) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      fullscreenDialog: true,
      opaque: false,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, _, child) {
        if (reduceMotion(context)) return child;
        final a = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
          child: FadeTransition(opacity: a, child: child),
        );
      },
    );

/// Lets the user pull the page down to close it.
class DragToDismiss extends StatefulWidget {
  const DragToDismiss({super.key, required this.child, required this.onDismiss});
  final Widget child;
  final VoidCallback onDismiss;

  @override
  State<DragToDismiss> createState() => _DragToDismissState();
}

class _DragToDismissState extends State<DragToDismiss> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() => setState(() => _dy = _from * (1 - Curves.easeOut.transform(_back.value))));
  double _dy = 0;
  double _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _end(DragEndDetails d) {
    final h = MediaQuery.sizeOf(context).height;
    if (_dy > h * 0.18 || (d.primaryVelocity ?? 0) > 900) {
      widget.onDismiss();
    } else {
      _from = _dy;
      _back.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(() => _dy = (_dy + d.delta.dy).clamp(0.0, h)),
      onVerticalDragEnd: _end,
      child: Transform.translate(
        offset: Offset(0, _dy),
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular((_dy / 4).clamp(0.0, 28.0))),
          child: widget.child,
        ),
      ),
    );
  }
}
