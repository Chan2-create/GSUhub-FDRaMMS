import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// "← Reports" under the header (Figma `169:1251`, "Group 26"): the back
/// arrow and the page's title. Shared by every page inside the requestor
/// shell so they line up.
class RequestorTitleRow extends StatelessWidget {
  const RequestorTitleRow({
    required this.title,
    required this.onBack,
    super.key,
    this.trailing,
  });

  final String title;
  final VoidCallback onBack;

  /// An action at the row's right end — Notifications' "Mark all as
  /// read" (3.B).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: SvgPicture.asset(
            'assets/icons/mobile_back.svg',
            width: 16,
            height: 16,
            colorFilter: const ColorFilter.mode(
              AppColors.myReportsTitle,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.myReportsTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing case final trailing?)
          Padding(padding: const EdgeInsets.only(right: 8), child: trailing),
      ],
    ),
  );
}
