import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

/// Shows the two phone apps (`/staff/*`, `/personnel/*`) as they were
/// drawn, on whatever phone they run on.
///
/// The mobile designs are 390 wide, with sizes and type fixed to that
/// width. On a narrower phone (most Android phones are 360) the same
/// numbers crowded every card: labels wrapped, hints were cut, the bottom
/// bar's names broke in two, and it all read as zoomed in (seen on a
/// 360-wide phone, 2026-11-12). Two things are done about it, here and
/// nowhere else:
///
/// * **Width.** Narrower than [designWidth], the app is laid out at the
///   design's width and scaled down to fit, so every screen keeps the
///   proportions it was drawn with. At the design's width or wider,
///   nothing is scaled.
/// * **Text size.** The phone's font-size setting is not allowed to make
///   text larger than drawn: the fixed-height cards, tiles and buttons
///   have no room for it (at 115% the sign-in button already wrapped; at
///   130% the home tiles overflowed). Smaller text is honoured.
///
/// The administrator console is left alone: it has its own layout for
/// every width (docs/architecture_decisions.md §24).
class PhoneViewport extends StatefulWidget {
  const PhoneViewport({required this.router, required this.child, super.key});

  /// Says which page is showing: only the phone apps' are fitted.
  final GoRouter router;

  final Widget child;

  /// The width the mobile screens were designed at.
  static const double designWidth = 390;

  /// Whether [path] is a page of the faculty and staff app or of the
  /// maintenance personnel app.
  static bool isPhonePage(String path) =>
      path.startsWith('/staff') || path.startsWith('/personnel');

  @override
  State<PhoneViewport> createState() => _PhoneViewportState();
}

class _PhoneViewportState extends State<PhoneViewport> {
  late bool _phonePage = _read();

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRoute);
  }

  @override
  void didUpdateWidget(PhoneViewport old) {
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
    return PhoneViewport.isPhonePage(
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
    final width = media.size.width;
    final scale = _phonePage && width > 0 && width < PhoneViewport.designWidth
        ? width / PhoneViewport.designWidth
        : 1.0;

    // The same widgets around the app on every page and at every width,
    // only with a scale of 1 where nothing is fitted: changing the shape
    // here would rebuild every open page from nothing.
    //
    // Everything a page measures itself by is given in the design's
    // units: the window, the notch and gesture areas, the keyboard.
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
