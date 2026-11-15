import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../di/service_providers.dart';

/// The GSUhub logo while the app starts (§38).
///
/// From the first frame until the session is known, Firebase is restoring
/// the sign-in and the router holds still; that gap used to be a blank
/// page. The logo now fades in and settles over it, stays at least as long
/// as its own entrance takes, and fades out the moment the session is
/// known, into the page the person was headed for. It is a real loading
/// state, not a timer: with the session already known it is gone after
/// one entrance. Under reduced motion nothing scales; the logo appears
/// and goes.
///
/// Driven by tickers, not timers, so it settles in tests and leaves
/// nothing pending.
class LaunchSplash extends ConsumerStatefulWidget {
  const LaunchSplash({required this.child, super.key});

  final Widget child;

  /// How long the logo takes to arrive, and the least it stays.
  static const Duration entrance = Duration(milliseconds: 900);

  /// How long it takes to leave.
  static const Duration exit = Duration(milliseconds: 350);

  @override
  ConsumerState<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends ConsumerState<LaunchSplash>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: LaunchSplash.entrance,
  );
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: LaunchSplash.exit,
  );
  bool _gone = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _enter.addStatusListener((_) => _maybeLeave());
    // The session becoming known is the other thing that lets it leave.
    ref.listenManual(authStateProvider, (_, _) => _maybeLeave());
    _leave.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _gone = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here, not in initState: the durations depend on the
    // person's motion setting, which only the tree knows.
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.duration = const Duration(milliseconds: 1);
      _leave.duration = const Duration(milliseconds: 120);
    }
    _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    _leave.dispose();
    super.dispose();
  }

  /// Leaves once the logo has arrived and the session is known.
  void _maybeLeave() {
    if (_gone || _leave.isAnimating || _leave.isCompleted) return;
    if (!_enter.isCompleted) return;
    if (ref.read(authStateProvider).isLoading) return;
    _leave.forward();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // Always the first child of the same Stack, before and after the
      // logo leaves: returning the page on its own once the logo had gone
      // moved it in the tree, and Flutter rebuilt everything under it
      // from scratch, open pages and their listeners included.
      widget.child,
      if (!_gone) _logo(context),
    ],
  );

  /// Over the page, and taking its taps, until it has gone.
  Widget _logo(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final arrival = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: ReverseAnimation(_leave),
      child: AbsorbPointer(
        child: ColoredBox(
          color: AppColors.surface,
          child: Center(
            child: FadeTransition(
              opacity: arrival,
              child: ScaleTransition(
                scale: reduced
                    ? const AlwaysStoppedAnimation(1)
                    : Tween<double>(begin: 0.92, end: 1).animate(arrival),
                child: Semantics(
                  label: 'GSUhub is starting',
                  image: true,
                  child: Image.asset(
                    'assets/images/gsuhub_logo.png',
                    key: const ValueKey('launch-logo'),
                    width: 168,
                    height: 168,
                    filterQuality: FilterQuality.high,
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
