import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/utils/display_id.dart';
import '../../../inventory/presentation/widgets/inventory_widgets.dart';
import '../../data/models/tool_request.dart';
import 'tool_dialogs.dart';

/// The pieces the console draws tool requests with (2026-11-16): the
/// status pill, a request in a tool's history, and the Tools tab's list
/// of requests still waiting for a technician.

final DateFormat _when = DateFormat('MMM d, y h:mm a');

/// A transaction's status, as the brief's table names it: gold while the
/// technician has something to do, red when it is late, green or blue
/// once confirmed, grey when it ended without a hand-over.
class ToolTransactionChip extends StatelessWidget {
  const ToolTransactionChip(this.status, {super.key});

  final ToolTransactionStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      ToolTransactionStatus.pendingConfirmation ||
      ToolTransactionStatus.awaitingReturn => (
        AppColors.inventoryLowStockFill,
        AppColors.inventoryLowStockText,
      ),
      ToolTransactionStatus.overdue => (
        AppColors.inventoryRepairFill,
        AppColors.inventoryRepairText,
      ),
      ToolTransactionStatus.borrowed => (
        AppColors.inventoryBorrowedFill,
        AppColors.inventoryBorrowedText,
      ),
      ToolTransactionStatus.returned => (
        AppColors.inventoryInStockFill,
        AppColors.inventoryInStockText,
      ),
      ToolTransactionStatus.cancelled || ToolTransactionStatus.expired => (
        AppColors.surfaceSunken,
        AppColors.inventoryLabel,
      ),
    };
    return InventoryBadge(
      label: status.label.toUpperCase(),
      background: background,
      foreground: foreground,
      horizontalPadding: 10,
    );
  }
}

/// What the request asked, in one line: "Collect on Nov 16, 2026 10:00 AM
/// · back by Nov 18, 2026 5:00 PM", or "Return by Nov 18, 2026 5:00 PM".
String toolRequestTiming(ToolRequest request) => switch (request.kind) {
  ToolRequestKind.checkOut => [
    if (request.checkoutAt case final at?)
      'Collect on ${_when.format(at.toLocal())}',
    if (request.dueAt case final at?) 'back by ${_when.format(at.toLocal())}',
  ].join(' · '),
  ToolRequestKind.checkIn =>
    'Return by ${_when.format(request.dueAt!.toLocal())}',
};

/// One request in a tool's history: the transaction, who, when it was
/// asked and how it ended, and what was said.
class ToolRequestHistoryRow extends StatelessWidget {
  const ToolRequestHistoryRow({
    required this.request,
    required this.names,
    super.key,
  });

  final ToolRequest request;

  /// Everyone's names by id: technicians and administrators.
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final technician = names[request.personnelId] ?? 'A technician';
    final asker = names[request.requestedBy] ?? 'An administrator';
    final ending = switch (request.status) {
      ToolRequestStatus.confirmed when request.confirmedAt != null =>
        'Confirmed by scanning ${request.qrCode} on '
            '${_when.format(request.confirmedAt!.toLocal())}',
      ToolRequestStatus.cancelled when request.closedAt != null =>
        'Cancelled by ${names[request.closedBy] ?? 'an administrator'} on '
            '${_when.format(request.closedAt!.toLocal())}',
      ToolRequestStatus.expired when request.closedAt != null =>
        'Lapsed uncollected on ${_when.format(request.closedAt!.toLocal())}',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${request.kind.label} · $technician',
                  style: AppTextStyles.inventoryCellStrong,
                ),
              ),
              ToolTransactionChip(request.statusAt(DateTime.now())),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              'Asked by $asker on ${_when.format(request.requestedAt.toLocal())}',
              toolRequestTiming(request),
              ?ending,
              if (request.purpose case final purpose?) 'Purpose: $purpose',
              if (request.workOrderId case final id?)
                'for ${DisplayId.workOrder(id)}',
              if (request.message case final message?) '“$message”',
            ].join(' · '),
            style: AppTextStyles.inventoryStatNote,
          ),
        ],
      ),
    );
  }
}

/// The Tools tab's requests still waiting for a technician (2026-11-16):
/// what is out for collection, what has been asked back, what is late.
/// Each can be cancelled. Hidden when nothing waits.
class ToolRequestsPanel extends ConsumerWidget {
  const ToolRequestsPanel({
    required this.requests,
    required this.names,
    super.key,
  });

  final List<ToolRequest> requests;

  /// Technicians' names by id.
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final late = requests
        .where(
          (request) => request.statusAt(now) == ToolTransactionStatus.overdue,
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InventorySectionHeader(title: 'Waiting for a Technician'),
        const SizedBox(height: 8),
        Text(
          [
            '${requests.length} request${requests.length == 1 ? '' : 's'} '
                'waiting for the technician to scan the tool and confirm',
            if (late > 0) '$late overdue',
          ].join(' · '),
          style: AppTextStyles.inventoryStatNote.copyWith(
            color: late > 0 ? AppColors.error : null,
          ),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.borderStrong),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (final (i, request) in requests.indexed) ...[
                if (i > 0)
                  const Divider(height: 1, color: AppColors.borderStrong),
                _OpenRequestRow(
                  request: request,
                  technician: names[request.personnelId] ?? 'A technician',
                  now: now,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OpenRequestRow extends ConsumerWidget {
  const _OpenRequestRow({
    required this.request,
    required this.technician,
    required this.now,
  });

  final ToolRequest request;
  final String technician;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = request.statusAt(now);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              request.kind.label.toUpperCase(),
              style: AppTextStyles.inventoryCaption,
            ),
            Text(
              '${request.toolName} · ${request.toolCode}',
              style: AppTextStyles.inventoryCellStrong,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            technician,
            toolRequestTiming(request),
            ?request.purpose,
          ].join(' · '),
          style: AppTextStyles.inventoryStatNote,
        ),
        if (request.message case final message?) ...[
          const SizedBox(height: 2),
          Text(
            '“$message”',
            style: AppTextStyles.inventoryStatNote.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolTransactionChip(status),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => showCancelToolRequestDialog(
            context,
            ref,
            request,
            technicianName: technician,
          ),
          child: const Text('Cancel'),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 560
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 8), actions],
              )
            : Row(
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  actions,
                ],
              ),
      ),
    );
  }
}
