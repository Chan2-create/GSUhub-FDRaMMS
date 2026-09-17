import 'package:flutter/material.dart';

/// Router outlet for the Admin web app. Deliberately has NO layout —
/// no sidebar, header, or navigation chrome. That is 1.1(c)'s
/// responsibility (manuscript §3.5 UI figures are unresolved; see
/// docs/architecture_decisions.md). This shell exists only so
/// `app_router.dart` has a `ShellRoute` builder to attach real layout to
/// later without touching the route table itself.
class AdminShell extends StatelessWidget {
  const AdminShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
