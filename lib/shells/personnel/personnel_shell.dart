import 'package:flutter/material.dart';

/// Router outlet for the GSU Maintenance Personnel mobile app. Deliberately
/// has NO layout — no bottom nav, no app bar. Real UI is Objective 5.x's
/// responsibility; this shell exists only so `app_router.dart` has a
/// branch to attach real layout to later without touching the route table
/// itself. Mirrors `shells/admin/admin_shell.dart`.
class PersonnelShell extends StatelessWidget {
  const PersonnelShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
