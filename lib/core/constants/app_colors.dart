import 'package:flutter/material.dart';

// TODO: pending design confirmation. Manuscript §3.5 contains duplicated
// and mislabeled figures for the Admin UI; the real palette is being
// resolved separately. These are neutral Material placeholders only, used
// by scaffolding placeholder screens — do not build real UI against them.
abstract final class AppColors {
  static const Color primary = Colors.indigo;
  static const Color surface = Colors.white;
  static const Color background = Color(0xFFF5F5F5);
  static const Color error = Colors.red;
}
