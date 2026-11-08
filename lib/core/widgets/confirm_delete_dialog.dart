import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../utils/result.dart';

/// Asks before a delete or an archive, does it, and says how it went
/// (2026-11-08): every delete in the console goes through here.
///
/// [title] names what goes ("Delete Fluke Multimeter?"); [message] says
/// what happens to it and what stays. A refusal (the database's: "on loan
/// to Marcus Wright. Check it in first.") shows in the dialog, which stays
/// open; success closes it and shows [doneMessage]. True once done.
Future<bool> showConfirmDeleteDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String doneMessage,
  required Future<Result<void>> Function() onConfirm,
  String confirmLabel = 'Delete',
  String busyLabel = 'Deleting…',
  bool destructive = true,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDeleteDialog(
        title: title,
        message: message,
        doneMessage: doneMessage,
        onConfirm: onConfirm,
        confirmLabel: confirmLabel,
        busyLabel: busyLabel,
        destructive: destructive,
      ),
    ) ??
    false;

class _ConfirmDeleteDialog extends StatefulWidget {
  const _ConfirmDeleteDialog({
    required this.title,
    required this.message,
    required this.doneMessage,
    required this.onConfirm,
    required this.confirmLabel,
    required this.busyLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String doneMessage;
  final Future<Result<void>> Function() onConfirm;
  final String confirmLabel;
  final String busyLabel;

  /// Red, for what removes something; a restore is not.
  final bool destructive;

  @override
  State<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends State<_ConfirmDeleteDialog> {
  String? _error;
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.onConfirm();
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messenger.showSnackBar(SnackBar(content: Text(widget.doneMessage)));
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message, style: AppTextStyles.bodyText),
          if (_error case final message?) ...[
            const SizedBox(height: 12),
            Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: widget.destructive
            ? FilledButton.styleFrom(backgroundColor: AppColors.error)
            : null,
        onPressed: _busy ? null : _confirm,
        child: Text(_busy ? widget.busyLabel : widget.confirmLabel),
      ),
    ],
  );
}
