import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../utils/initials.dart';

/// A person's initials in a rounded tile (Figma `201:4753`).
///
/// The designs show photographs, but no account carries one — `users`
/// has no photo field — so the tile shows what the data does hold. Shared
/// by the Task Assignment panel and the Personnel directory.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({required this.fullName, super.key, this.isActive = true});

  final String fullName;

  /// Inactive accounts are drawn greyed.
  final bool isActive;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: isActive ? AppColors.avatarBackground : AppColors.borderSubtle,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      initialsOf(fullName),
      style: AppTextStyles.avatarInitials.copyWith(
        color: isActive ? AppColors.primary : AppColors.textFaint,
      ),
    ),
  );
}
