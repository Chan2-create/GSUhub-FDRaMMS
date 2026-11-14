import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Asks before logging out, on the console and on the phone alike: one
/// press on a menu or a button should not end a session. True when the
/// person confirms; false when they cancel or dismiss the dialog.
Future<bool> confirmSignOut(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out of GSUhub?'),
        content: const Text('You will need to sign in again to come back.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnDark,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    ) ??
    false;
