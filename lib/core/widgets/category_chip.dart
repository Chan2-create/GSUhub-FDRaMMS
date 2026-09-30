import 'package:flutter/material.dart';

import '../constants/app_text_styles.dart';
import '../constants/damage_categories.dart';

/// Soft background and strong foreground for one damage category.
typedef CategoryColors = ({Color background, Color foreground});

/// A damage category as a pill — "ELECTRICAL" (Figma `200:4316`).
///
/// One palette for the whole app, so a category reads the same colour on
/// the personnel table and in Analytics. Taken from the Personnel frame,
/// the only design that ties colours to the manuscript's real categories:
/// it draws four of the seven (electrical, plumbing, air conditioning as
/// "HVAC", general as "GENERAL"). Structural, carpentry and cleaning follow
/// the same pale-fill, dark-text pattern.
class CategoryChip extends StatelessWidget {
  const CategoryChip({required this.category, super.key});

  final DamageCategory category;

  static CategoryColors colorsOf(DamageCategory category) => switch (category) {
    DamageCategory.electrical => (
      background: const Color(0xFFEFF6FF),
      foreground: const Color(0xFF1E40AF),
    ),
    DamageCategory.plumbing => (
      background: const Color(0xFFFFF7ED),
      foreground: const Color(0xFF9A3412),
    ),
    DamageCategory.structural => (
      background: const Color(0xFFF5F3FF),
      foreground: const Color(0xFF5B21B6),
    ),
    DamageCategory.carpentry => (
      background: const Color(0xFFFFFBEB),
      foreground: const Color(0xFF92400E),
    ),
    DamageCategory.airConditioning => (
      background: const Color(0xFFF0FDFA),
      foreground: const Color(0xFF115E59),
    ),
    DamageCategory.cleaningAndSanitation => (
      background: const Color(0xFFF0FDF4),
      foreground: const Color(0xFF166534),
    ),
    DamageCategory.generalMaintenance => (
      background: const Color(0xFFF1F5F9),
      foreground: const Color(0xFF1E293B),
    ),
  };

  /// The pill's short label. The design abbreviates where the full name
  /// would not fit its column — "HVAC", "GENERAL" — and the rest follow.
  static String shortLabelOf(DamageCategory category) => switch (category) {
    DamageCategory.electrical => 'ELECTRICAL',
    DamageCategory.plumbing => 'PLUMBING',
    DamageCategory.structural => 'STRUCTURAL',
    DamageCategory.carpentry => 'CARPENTRY',
    DamageCategory.airConditioning => 'HVAC',
    DamageCategory.cleaningAndSanitation => 'CLEANING',
    DamageCategory.generalMaintenance => 'GENERAL',
  };

  /// A glyph per category, for the Analytics issue list.
  static IconData iconOf(DamageCategory category) => switch (category) {
    DamageCategory.electrical => Icons.bolt,
    DamageCategory.plumbing => Icons.water_drop_outlined,
    DamageCategory.structural => Icons.foundation,
    DamageCategory.carpentry => Icons.carpenter,
    DamageCategory.airConditioning => Icons.ac_unit,
    DamageCategory.cleaningAndSanitation => Icons.cleaning_services_outlined,
    DamageCategory.generalMaintenance => Icons.handyman_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(category);
    return Tooltip(
      message: category.label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          shortLabelOf(category),
          style: AppTextStyles.categoryChip.copyWith(color: colors.foreground),
          maxLines: 1,
        ),
      ),
    );
  }
}
