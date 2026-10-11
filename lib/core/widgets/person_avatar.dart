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
  const PersonAvatar({
    required this.fullName,
    super.key,
    this.isActive = true,
    this.size = 40,
    this.ringColor,
  });

  final String fullName;

  /// Inactive accounts are drawn greyed.
  final bool isActive;

  final double size;

  /// When given, the avatar is a circle with a ring of this colour — the
  /// faculty app's staff card (Figma `169:1052`) — rather than a tile.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: isActive ? AppColors.avatarBackground : AppColors.borderSubtle,
      shape: ringColor == null ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: ringColor == null ? BorderRadius.circular(12) : null,
      border: ringColor == null
          ? null
          : Border.all(color: ringColor!, width: 2),
    ),
    child: Text(
      initialsOf(fullName),
      style: AppTextStyles.avatarInitials.copyWith(
        color: isActive ? AppColors.primary : AppColors.textFaint,
      ),
    ),
  );
}
