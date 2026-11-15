import 'package:flutter/material.dart';

/// The platform's own page transition, or none at all when the person has
/// asked their system for reduced motion (§39).
///
/// The framework's page transitions do not read that setting themselves,
/// so a phone set to "Remove animations", or a browser that prefers
/// reduced motion, still saw every page slide and fade. Wrapped around
/// each platform's default, this changes nothing for anyone else: the
/// same transition, the same durations, the same predictive back on
/// Android. Under reduced motion the new page is simply there.
class ReducedMotionTransitions extends PageTransitionsBuilder {
  const ReducedMotionTransitions(this.inner);

  /// The transition used when motion is welcome.
  final PageTransitionsBuilder inner;

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  // A tear-off of the same object's method is equal each time it is
  // taken, so routes comparing one page's transition with the next see
  // no change where there is none.
  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      inner.delegatedTransition == null ? null : _delegated;

  Widget? _delegated(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) => MediaQuery.disableAnimationsOf(context)
      ? child
      : inner.delegatedTransition!(
          context,
          animation,
          secondaryAnimation,
          allowSnapshotting,
          child,
        );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => MediaQuery.disableAnimationsOf(context)
      ? child
      : inner.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}
