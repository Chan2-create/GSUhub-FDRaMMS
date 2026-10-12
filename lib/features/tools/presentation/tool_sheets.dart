import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/enums/item_condition.dart';
import '../../../core/utils/display_id.dart';
import '../../../core/utils/result.dart';
import '../../work_orders/data/models/work_order.dart';
import '../../work_orders/presentation/personnel/personnel_providers.dart';
import '../../work_orders/presentation/personnel/personnel_work_controller.dart';
import '../../work_orders/presentation/personnel/widgets/personnel_widgets.dart';
import '../data/models/tool.dart';
import '../data/models/tool_loan.dart';

/// Borrowing a tool (Objective 5.C), from a scan or a work order's page.
/// With no [tool], the technician picks one on the shelf; [workOrderId]
/// preselects the work it is for. Not in the design: a plain sheet in the
/// app's style, flagged.
Future<void> showBorrowToolSheet(
  BuildContext context, {
  Tool? tool,
  String? workOrderId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _BorrowToolSheet(tool: tool, workOrderId: workOrderId),
);

class _BorrowToolSheet extends ConsumerStatefulWidget {
  const _BorrowToolSheet({required this.tool, required this.workOrderId});

  final Tool? tool;
  final String? workOrderId;

  @override
  ConsumerState<_BorrowToolSheet> createState() => _BorrowToolSheetState();
}

class _BorrowToolSheetState extends ConsumerState<_BorrowToolSheet> {
  late Tool? _tool = widget.tool;
  late String? _workOrderId = widget.workOrderId;
  bool _busy = false;
  String? _error;

  Future<void> _borrow() async {
    final tool = _tool;
    if (tool == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(personnelWorkControllerProvider)
        .borrowTool(toolId: tool.id, workOrderId: _workOrderId);
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop();
        showPersonnelMessage(
          context,
          'You have ${tool.name}. Return it from the Materials tab.',
        );
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tool = _tool;
    final open = switch (ref.watch(myWorkOrdersProvider)) {
      AsyncData(value: Success(:final value)) => [
        for (final order in value)
          if (MyWork.isOpen(order.status)) order,
      ],
      _ => const <WorkOrder>[],
    };

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Borrow a tool',
                style: AppTextStyles.personnelSection,
              ),
              const SizedBox(height: 4),
              const Text(
                'It is recorded against you until you return it, with the '
                'condition it is in now.',
                style: AppTextStyles.personnelCardBody,
              ),
              const SizedBox(height: 16),
              if (tool == null)
                _ToolPicker(
                  onPicked: (picked) => setState(() => _tool = picked),
                )
              else ...[
                PersonnelCard(
                  color: AppColors.personnelTile,
                  child: ToolSummary(tool: tool),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _workOrderId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'For work order',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(child: Text('None')),
                    for (final order in open)
                      DropdownMenuItem(
                        value: order.id,
                        child: Text(
                          '${DisplayId.workOrder(order.id)} · ${order.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (id) => setState(() => _workOrderId = id),
                ),
                if (_error case final message?) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: AppTextStyles.personnelCardBody.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || !tool.status.isIssuable ? null : _borrow,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(_busy ? 'Saving…' : 'Borrow'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tool's name, code, condition and where it is kept.
class ToolSummary extends StatelessWidget {
  const ToolSummary({required this.tool, super.key});

  final Tool tool;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.handyman_outlined, color: AppColors.personnelTitle),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tool.name, style: AppTextStyles.personnelCardTitle),
            const SizedBox(height: 2),
            Text(
              [
                tool.toolCode,
                '${tool.condition.label} condition',
                ?tool.storageLocation,
              ].join(' · '),
              style: AppTextStyles.personnelCardBody,
            ),
          ],
        ),
      ),
      PersonnelChip(
        tool.status.label,
        background: tool.status.isIssuable
            ? AppColors.personnelStockFill
            : AppColors.personnelUrgentFill,
        foreground: tool.status.isIssuable
            ? AppColors.personnelStockText
            : AppColors.personnelUrgentText,
      ),
    ],
  );
}

class _ToolPicker extends ConsumerWidget {
  const _ToolPicker({required this.onPicked});

  final ValueChanged<Tool> onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref.watch(
    availableToolsProvider,
  )) {
    AsyncData(value: Success(:final value)) when value.isEmpty => const Text(
      'No tool is on the shelf right now.',
      style: AppTextStyles.personnelCardBody,
    ),
    AsyncData(value: Success(:final value)) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tool in value)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.handyman_outlined),
            title: Text(tool.name),
            subtitle: Text(
              '${tool.toolCode} · ${tool.condition.label} condition',
            ),
            onTap: () => onPicked(tool),
          ),
      ],
    ),
    AsyncData(value: Error(:final failure)) => Text(
      'The tools could not be read. ${failure.message}',
      style: AppTextStyles.personnelCardBody,
    ),
    AsyncError(:final error) => Text(
      'The tools could not be read. $error',
      style: AppTextStyles.personnelCardBody,
    ),
    _ => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    ),
  };
}

/// Returning a tool: what condition it comes back in, and a note (5.C).
/// Poor sends it to repair rather than back on the shelf.
Future<void> showReturnToolSheet(BuildContext context, ToolLoan loan) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _ReturnToolSheet(loan: loan),
      ),
    );

class _ReturnToolSheet extends ConsumerStatefulWidget {
  const _ReturnToolSheet({required this.loan});

  final ToolLoan loan;

  @override
  ConsumerState<_ReturnToolSheet> createState() => _ReturnToolSheetState();
}

class _ReturnToolSheetState extends ConsumerState<_ReturnToolSheet> {
  late ItemCondition _condition = widget.loan.conditionOnBorrow;
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _return() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final notes = _notes.text.trim();
    final result = await ref
        .read(personnelWorkControllerProvider)
        .returnTool(
          loanId: widget.loan.id,
          condition: _condition,
          notes: notes.isEmpty ? null : notes,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop();
        showPersonnelMessage(context, '${widget.loan.toolName} returned.');
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Return ${loan.toolName}',
              style: AppTextStyles.personnelSection,
            ),
            const SizedBox(height: 4),
            Text(
              'Borrowed ${DateFormat('MMM d, h:mm a').format(loan.borrowedAt.toLocal())} '
              'in ${loan.conditionOnBorrow.label.toLowerCase()} condition.',
              style: AppTextStyles.personnelCardBody,
            ),
            const SizedBox(height: 16),
            const Text('CONDITION NOW', style: AppTextStyles.personnelChip),
            const SizedBox(height: 8),
            SegmentedButton<ItemCondition>(
              segments: [
                for (final condition in ItemCondition.values)
                  ButtonSegment(value: condition, label: Text(condition.label)),
              ],
              selected: {_condition},
              showSelectedIcon: false,
              onSelectionChanged: _busy
                  ? null
                  : (selection) =>
                        setState(() => _condition = selection.single),
            ),
            if (_condition == ItemCondition.poor) ...[
              const SizedBox(height: 8),
              const Text(
                'A tool returned in poor condition goes to repair.',
                style: AppTextStyles.personnelCardBody,
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              enabled: !_busy,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Anything GSU should know about it',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: AppTextStyles.personnelCardBody.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _return,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(_busy ? 'Saving…' : 'Return'),
            ),
          ],
        ),
      ),
    );
  }
}
