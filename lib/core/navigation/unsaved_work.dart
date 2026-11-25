import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';

/// Forms on screen that may hold work not yet saved (2026-11-25), asked
/// before a navigation button takes the person off the page they are on.
///
/// A form joins with [GuardsUnsavedWork] and answers
/// [GuardsUnsavedWork.hasUnsavedWork] when asked, at the moment of the
/// tap, so nothing has to rebuild to keep this up to date. A form in a
/// dialog or a sheet does not need to join: the dialog's barrier keeps the
/// navigation out of reach until it is closed.
class UnsavedWork {
  final Set<GuardsUnsavedWork> _forms = {};

  /// Whether any form on screen holds unsaved work now.
  bool get any => _forms.any((form) => form.mounted && form.hasUnsavedWork);

  void _join(GuardsUnsavedWork form) => _forms.add(form);
  void _leave(GuardsUnsavedWork form) => _forms.remove(form);
}

final unsavedWorkProvider = Provider<UnsavedWork>((ref) => UnsavedWork());

/// A form that may hold unsaved work: it is asked before the page it is on
/// is left from the navigation (see [confirmLeavingUnsavedWork]).
mixin GuardsUnsavedWork<T extends StatefulWidget> on State<T> {
  UnsavedWork? _registry;

  /// Whether what is typed or chosen here differs from what is saved, or,
  /// for a new record, whether anything has been entered at all.
  bool get hasUnsavedWork;

  @override
  void initState() {
    super.initState();
    final registry = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(unsavedWorkProvider);
    registry._join(this);
    _registry = registry;
  }

  @override
  void dispose() {
    _registry?._leave(this);
    super.dispose();
  }
}

/// Asks before leaving a page with unsaved work on it. True when there is
/// none, or the person chose to leave and discard it; false when they
/// chose to stay, in which case nothing is touched.
Future<bool> confirmLeavingUnsavedWork(BuildContext context) async {
  final unsaved = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(unsavedWorkProvider);
  if (!unsaved.any) return true;
  final leave = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Leave without saving?'),
      content: const Text(
        'You have changes on this page that are not saved yet. If you '
        'leave now, they will be lost.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Stay on this page'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Leave and discard'),
        ),
      ],
    ),
  );
  return leave ?? false;
}
