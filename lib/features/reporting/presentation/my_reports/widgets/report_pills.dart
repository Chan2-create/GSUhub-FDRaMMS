import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/constants/damage_categories.dart';
import '../../../../../core/widgets/category_chip.dart';
import '../../../data/models/damage_report.dart';

/// The damage type a requestor's report shows: the administrator's
/// confirmed category once there is one, otherwise the type the requestor
/// suggested (3.C). Null when neither exists yet.
DamageCategory? shownCategoryOf(DamageReport report) =>
    report.category ?? report.requestorCategory;

/// A category in the faculty and staff app's words — "Electrical", "HVAC"
/// — the admin console's short labels in sentence case.
String requestorCategoryLabel(DamageCategory category) {
  final short = CategoryChip.shortLabelOf(category);
  return category == DamageCategory.airConditioning
      ? short
      : short[0] + short.substring(1).toLowerCase();
}

/// The home screen's category pill: white on navy (Figma `170:2050`).
class HomeCategoryPill extends StatelessWidget {
  const HomeCategoryPill({required this.category, super.key});

  final DamageCategory category;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      requestorCategoryLabel(category),
      style: AppTextStyles.requestorChip.copyWith(color: Colors.white),
    ),
  );
}

/// My Reports' category pill: brown on sand (Figma `169:1251`).
class MyReportsCategoryPill extends StatelessWidget {
  const MyReportsCategoryPill({required this.category, super.key});

  final DamageCategory category;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.warmFill,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      requestorCategoryLabel(category),
      style: AppTextStyles.myReportsCategory,
    ),
  );
}

/// Where a report is, as its card heads it — "AB Bldg, Room 101".
String reportPlaceOf(DamageReport report) =>
    report.locationDescription ?? report.facilityName ?? report.title;
