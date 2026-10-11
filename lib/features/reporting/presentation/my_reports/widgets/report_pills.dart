import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/constants/damage_categories.dart';
import '../../../../../core/enums/report_status.dart';
import '../../../../../core/widgets/category_chip.dart';
import '../../../data/models/damage_report.dart';

/// The damage type a requestor's report card shows: the one GSU confirmed
/// once there is one, otherwise the type the requestor suggested (3.C).
/// Never the keyword classifier's unreviewed guess (3.B). Null when
/// neither exists yet.
DamageCategory? shownCategoryOf(DamageReport report) =>
    confirmedCategoryOf(report) ?? report.requestorCategory;

/// The damage type GSU has decided on, or null until it has (Objective
/// 3.B): an administrator set it by hand, or approved the report with it.
/// The keyword classifier's guess (Objective 4) on a report still in
/// review — or one turned down, merged or archived — is not GSU's
/// decision, so the detail page does not present it as one.
DamageCategory? confirmedCategoryOf(DamageReport report) {
  final category = report.category;
  if (category == null || report.reviewedBy == null) return null;
  final approved = switch (report.status.progress) {
    ReportProgress.inProgress || ReportProgress.completed => true,
    ReportProgress.pending || ReportProgress.closedOut => false,
  };
  return approved || !report.classifiedAutomatically ? category : null;
}

/// The room part of where a report was filed: what its location says
/// beyond the building's own name — "Engineering Building, Room 101" gives
/// "Room 101". Null when the location names only the building.
String? roomOf(DamageReport report) {
  final location = report.locationDescription?.trim();
  if (location == null || location.isEmpty) return null;
  final building = report.facilityName?.trim();
  if (building == null || building.isEmpty) return location;
  if (location == building) return null;
  final prefix = '$building, ';
  return location.startsWith(prefix)
      ? location.substring(prefix.length)
      : location;
}

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
