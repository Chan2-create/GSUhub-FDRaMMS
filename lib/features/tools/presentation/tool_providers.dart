import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/repository_providers.dart';
import '../../../core/utils/result.dart';
import '../data/models/tool.dart';
import '../data/models/tool_loan.dart';

/// What the console's tool screens read (Objective 6.B), all live. Moved
/// here from the inventory providers on 2026-11-14, so the tools feature
/// holds its own state; the personnel app's own loans are
/// `myToolLoansProvider`, beside its other providers.

/// Every tool, by tool ID.
final allToolsProvider = StreamProvider.autoDispose<Result<List<Tool>>>(
  (ref) => ref.watch(toolRepositoryProvider).watchTools(),
);

/// One tool, for its details dialog.
final toolProvider = StreamProvider.autoDispose.family<Result<Tool>, String>(
  (ref, id) => ref.watch(toolRepositoryProvider).watchTool(id),
);

/// Loans not yet returned, newest first.
final openLoansProvider = StreamProvider.autoDispose<Result<List<ToolLoan>>>(
  (ref) => ref.watch(toolRepositoryProvider).watchOpenLoans(),
);

/// One tool's loans, newest first, for its details dialog.
final toolLoanHistoryProvider = StreamProvider.autoDispose
    .family<Result<List<ToolLoan>>, String>(
      (ref, id) => ref.watch(toolRepositoryProvider).watchLoanHistory(id),
    );
