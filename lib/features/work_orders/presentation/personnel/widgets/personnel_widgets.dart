import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/di/service_providers.dart';
import '../../../../../core/enums/priority_level.dart';
import '../../../../../core/enums/work_order_status.dart';
import '../../../../../core/services/photo_picker_service.dart';
import '../../../../../core/utils/result.dart';

/// Building blocks the personnel pages share (Objective 5; Figures 24–25).

/// A white card with rounded corners and, optionally, a coloured left
/// edge — the to-do and work-order cards.
class PersonnelCard extends StatelessWidget {
  const PersonnelCard({
    required this.child,
    super.key,
    this.edge,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final Color? edge;
  final Color color;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final edgeColor = edge;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: edgeColor == null
                ? null
                : Border(left: BorderSide(color: edgeColor, width: 4)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Small capitals on a pill: a damage type, a priority, a stock level.
class PersonnelChip extends StatelessWidget {
  const PersonnelChip(
    this.label, {
    super.key,
    this.background = AppColors.personnelChip,
    this.foreground = AppColors.personnelChipText,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.personnelChip.copyWith(color: foreground),
      ),
    ),
  );
}

/// A work order's priority as Figure 25 words it: "HIGH PRIORITY" in red
/// for high and critical, "STANDARD" otherwise.
class PriorityTag extends StatelessWidget {
  const PriorityTag(this.priority, {super.key});

  final PriorityLevel priority;

  static bool isUrgent(PriorityLevel priority) =>
      priority == PriorityLevel.high || priority == PriorityLevel.critical;

  @override
  Widget build(BuildContext context) => isUrgent(priority)
      ? PersonnelChip(
          priority == PriorityLevel.critical ? 'Critical' : 'High priority',
          background: AppColors.personnelUrgentFill,
          foreground: AppColors.personnelUrgentText,
        )
      : const PersonnelChip(
          'Standard',
          background: AppColors.personnelToggleTrack,
          foreground: AppColors.homeSectionTitle,
        );
}

/// How the personnel app names a work order's status.
String workStatusLabel(WorkOrderStatus status) => switch (status) {
  WorkOrderStatus.pending => 'Pending',
  WorkOrderStatus.inProgress => 'In progress',
  WorkOrderStatus.forReview => 'Awaiting sign-off',
  WorkOrderStatus.completed => 'Completed',
};

/// The dot colour for a work order's status.
Color workStatusColor(WorkOrderStatus status) => switch (status) {
  WorkOrderStatus.pending => AppColors.personnelTile,
  WorkOrderStatus.inProgress => AppColors.personnelHighlight,
  WorkOrderStatus.forReview => AppColors.progressInProgress,
  WorkOrderStatus.completed => AppColors.progressCompleted,
};

/// "Upload Proof" — the outlined gold button on a task (Figure 24).
class UploadProofButton extends StatelessWidget {
  const UploadProofButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.upload_rounded, size: 16),
    label: const Text('Upload Proof'),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.trackingAccentText,
      side: const BorderSide(color: AppColors.personnelProofBorder),
      backgroundColor: Colors.white,
      minimumSize: const Size(48, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: AppTextStyles.personnelCardBody.copyWith(
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

/// A section heading with an optional action on the right.
class PersonnelSectionTitle extends StatelessWidget {
  const PersonnelSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, style: AppTextStyles.personnelSection),
        ),
      ),
      ?trailing,
    ],
  );
}

/// Asks camera or gallery, then picks up to [limit] photos. Null when the
/// person backed out; a failure (a refused permission) is shown here.
Future<List<PickedPhoto>?> pickPhotos(
  BuildContext context,
  WidgetRef ref, {
  required int limit,
}) async {
  final source = await showModalBottomSheet<PhotoSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.of(context).pop(PhotoSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  final picked = await ref
      .read(photoPickerServiceProvider)
      .pick(source, limit: limit);
  if (!context.mounted) return null;
  switch (picked) {
    case Success(:final value):
      return value.isEmpty ? null : value;
    case Error(:final failure):
      showPersonnelMessage(context, failure.message, isError: true);
      return null;
  }
}

/// A snackbar, red for a failure.
void showPersonnelMessage(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
}

/// Shows [result]'s failure, or [success] when given.
bool reportOutcome(
  BuildContext context,
  Result<void> result, {
  String? success,
}) {
  if (!context.mounted) return false;
  switch (result) {
    case Success():
      if (success != null) showPersonnelMessage(context, success);
      return true;
    case Error(:final failure):
      showPersonnelMessage(context, failure.message, isError: true);
      return false;
  }
}
