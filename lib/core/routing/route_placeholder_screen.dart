import 'package:flutter/material.dart';

/// Bare route target shared by all three shells until each route's owning
/// WBS objective builds the real screen. Intentionally minimal — no
/// layout, no styling decisions — per this session's scope: architecture
/// scaffolding only. Visual design is pending confirmation (manuscript
/// §3.5 figures are duplicated/mislabeled; see docs/architecture_decisions.md).
class RoutePlaceholderScreen extends StatelessWidget {
  const RoutePlaceholderScreen({required this.routeName, super.key});

  /// Label shown on screen, identifying which route resolved here.
  final String routeName;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(routeName)));
}
