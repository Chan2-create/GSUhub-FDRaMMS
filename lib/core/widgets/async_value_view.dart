import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../errors/failures.dart';
import '../utils/result.dart';

/// Renders the loading / empty / error / data states of a repository-backed
/// value, so no screen has to reinvent them.
///
/// Every data-backed element in the admin UI goes through this. Writing the
/// four states by hand per widget is how an app ends up with a spinner in
/// one place, a blank rectangle in another, and a red exception dump in a
/// third — and how an empty seeded database produces a screen that looks
/// broken rather than simply empty.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    required this.value,
    required this.data,
    super.key,
    this.isEmpty,
    this.emptyMessage = 'Nothing to show yet.',
    this.emptyIcon = Icons.inbox_outlined,
    this.loadingHeight = 160,
    this.onRetry,
  });

  /// The Riverpod async value being rendered. Its data is a [Result] so
  /// repository failures arrive as values, not thrown exceptions.
  final AsyncValue<Result<T>> value;

  /// Builds the success state.
  final Widget Function(T data) data;

  /// Whether a successfully loaded [T] should be treated as empty. Given a
  /// list, this is usually `(list) => list.isEmpty`.
  final bool Function(T data)? isEmpty;

  final String emptyMessage;
  final IconData emptyIcon;
  final double loadingHeight;

  /// Shown as a "Try again" action on the error state when provided.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => _Loading(height: loadingHeight),
    // An error thrown *outside* the Result (a provider that blew up rather
    // than a repository returning a failure) is still a real error the
    // user must see, so it gets the same treatment.
    error: (error, _) => _Error(message: '$error', onRetry: onRetry),
    data: (result) => result.fold(
      (payload) => isEmpty?.call(payload) ?? false
          ? _Empty(message: emptyMessage, icon: emptyIcon)
          : data(payload),
      (failure) => _Error(message: _messageFor(failure), onRetry: onRetry),
    ),
  );

  /// Failures already carry user-facing copy from `FirebaseErrorMapper`;
  /// this only adds the bit of context that depends on where it surfaced.
  static String _messageFor(Failure failure) => switch (failure) {
    NetworkFailure() => '${failure.message} This screen needs a connection.',
    PermissionFailure() => failure.message,
    _ => failure.message,
  };
}

class _Loading extends StatelessWidget {
  const _Loading({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 32, color: AppColors.textFaint),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall,
        ),
      ],
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 32, color: AppColors.error),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall,
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ],
    ),
  );
}
