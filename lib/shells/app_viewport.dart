import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/breakpoints.dart';

/// Sets the size the app is drawn at, around every page: the two phone
/// apps as they were designed, and the administrator console a step
/// smaller than drawn.
///
/// **The phone apps** (`/staff/*`, `/personnel/*`). The mobile designs
/// are 390 wide, with sizes and type fixed to that width. On a narrower
/// phone (most Android phones are 360) the same numbers crowded every
/// card: labels wrapped, hints were cut, the bottom bar's names broke in
/// two, and it all read as zoomed in (seen on a 360-wide phone,
/// 2026-11-12). So:
///
/// * narrower than [phoneDesignWidth], the app is laid out at the
///   design's width and scaled down to fit, and every screen keeps the
///   proportions it was drawn with; at that width or wider nothing is
///   scaled;
/// * the phone's font-size setting is not allowed to make text larger
///   than drawn: the fixed-height cards, tiles and buttons have no room
///   for it. Smaller text is honoured.
///
/// **The console** (everything else). Drawn at the Figma sizes it read as
/// zoomed in on a laptop: a 305px sidebar and an 80px header leave little
/// of a 1536px screen for the work (2026-11-13). On anything wider than a
/// phone it is laid out in a window [consoleScale] times larger and
/// scaled to fit, so every page is the same design at 90%, with more of
/// it on screen. A phone-width window keeps the console's own phone
/// layout at full size, where the type is already small.
///
/// The same widgets wrap the app on every page and at every width, with a
/// scale of 1 where nothing is fitted: changing the shape here would
/// rebuild every open page from nothing.
class AppViewport extends StatefulWidget {
  const AppViewport({required this.router, required this.child, super.key});

  /// Says which page is showing: a phone app's, or the console's.
  final GoRouter router;

  final Widget child;

  /// The width the mobile screens were designed at.
  static const double phoneDesignWidth = 390;

  /// The console's size against its design: nine tenths. The one number
  /// to change to make the whole console larger or smaller.
  static const double consoleScale = 0.9;

  /// Whether [path] is a page of the faculty and staff app or of the
  /// maintenance personnel app.
  static bool isPhonePage(String path) =>
      path.startsWith('/staff') || path.startsWith('/personnel');

  /// The scale a page is drawn at in a window [width] wide.
  static double scaleFor({required bool phonePage, required double width}) {
    if (width <= 0) return 1;
    if (phonePage) {
      return width < phoneDesignWidth ? width / phoneDesignWidth : 1;
    }
    // Decided by the real window: a phone-width window is not scaled, so
    // the console's phone layout is never both small and scaled.
    return width >= Breakpoints.compact ? consoleScale : 1;
  }

  @override
  State<AppViewport> createState() => _AppViewportState();
}

class _AppViewportState extends State<AppViewport> {
  late bool _phonePage = _read();

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRoute);
  }

  @override
  void didUpdateWidget(AppViewport old) {
    super.didUpdateWidget(old);
    if (old.router == widget.router) return;
    old.router.routerDelegate.removeListener(_onRoute);
    widget.router.routerDelegate.addListener(_onRoute);
    _phonePage = _read();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRoute);
    super.dispose();
  }

  /// The page showing now; before the router has placed its first page,
  /// the one it was asked to open.
  bool _read() {
    final router = widget.router;
    final shown = router.routerDelegate.currentConfiguration.uri.path;
    return AppViewport.isPhonePage(
      shown.isEmpty ? router.routeInformationProvider.value.uri.path : shown,
    );
  }

  void _onRoute() {
    if (_read() == _phonePage) return;
    void apply() {
      if (!mounted) return;
      final next = _read();
      if (next != _phonePage) setState(() => _phonePage = next);
    }

    // The router reports its first page while it is being built; a
    // rebuild asked for then has to wait for the frame to finish.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = AppViewport.scaleFor(
      phonePage: _phonePage,
      width: media.size.width,
    );

    // Everything a page measures itself by is given in its own units:
    // the window, the notch and gesture areas, the keyboard.
    final size = media.size / scale;
    return FittedBox(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: MediaQuery(
          data: media.copyWith(
            textScaler: _phonePage
                ? media.textScaler.clamp(maxScaleFactor: 1)
                : media.textScaler,
            size: size,
            devicePixelRatio: media.devicePixelRatio * scale,
            padding: media.padding / scale,
            viewPadding: media.viewPadding / scale,
            viewInsets: media.viewInsets / scale,
            systemGestureInsets: media.systemGestureInsets / scale,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
