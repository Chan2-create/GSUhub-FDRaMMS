import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'session_watch.dart';

/// Hears everything the person does, around every page of every app, and
/// tells [SessionWatch]: pointer presses, drags and taps, mouse movement,
/// scrolling, keys, and the page changing. Also when a phone app returns
/// to the foreground, so a session that ended while it slept is noticed
/// at once.
///
/// It consumes nothing: pointer events pass through to the page, and the
/// key handler answers false.
class SessionActivityListener extends ConsumerStatefulWidget {
  const SessionActivityListener({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<SessionActivityListener> createState() =>
      _SessionActivityListenerState();
}

class _SessionActivityListenerState
    extends ConsumerState<SessionActivityListener> {
  late final AppLifecycleListener _lifecycle;

  SessionWatch get _watch => ref.read(sessionWatchProvider);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _lifecycle = AppLifecycleListener(onResume: () => _watch.resumed());
    _attach(widget.router);
  }

  @override
  void didUpdateWidget(SessionActivityListener old) {
    super.didUpdateWidget(old);
    if (old.router == widget.router) return;
    old.router.routerDelegate.removeListener(_onNavigation);
    _attach(widget.router);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    widget.router.routerDelegate.removeListener(_onNavigation);
    _lifecycle.dispose();
    super.dispose();
  }

  void _attach(GoRouter router) {
    router.routerDelegate.addListener(_onNavigation);
    _watch.attach(
      location: () => router.routerDelegate.currentConfiguration.uri.toString(),
      go: router.go,
    );
  }

  bool _onKey(KeyEvent event) {
    _watch.activity();
    return false;
  }

  /// The router reports a page change while it is being built; what the
  /// activity may rebuild (the warning) has to wait for the frame to end.
  void _onNavigation() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _watch.activity();
      });
    } else {
      _watch.activity();
    }
  }

  void _onPointer(PointerEvent event) => _watch.activity();

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onPointer,
    onPointerMove: _onPointer,
    onPointerHover: _onPointer,
    onPointerSignal: _onPointer,
    child: widget.child,
  );
}
