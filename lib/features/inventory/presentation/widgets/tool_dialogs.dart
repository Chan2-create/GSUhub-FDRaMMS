import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/enums/account_status.dart';
import '../../../../core/enums/item_condition.dart';
import '../../../../core/enums/tool_status.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../audit/data/models/audit_actor.dart';
import '../../../qr_labels/qr_label.dart';
import '../../../qr_labels/qr_label_actions.dart';
import '../../../tools/data/models/tool.dart';
import '../../../tools/data/models/tool_draft.dart';
import '../../../tools/data/models/tool_loan.dart';
import '../../../user_management/data/models/app_user.dart';
import '../../../user_management/presentation/personnel_providers.dart';
import '../../../work_orders/data/models/work_order.dart';
import '../../../work_orders/presentation/personnel/personnel_providers.dart'
    show MyWork;
import '../../../work_orders/presentation/work_order_providers.dart';
import '../inventory_controller.dart';
import '../inventory_providers.dart';
import 'inventory_widgets.dart';

/// The tool dialogs of the Inventory page (Objective 6.B): adding and
/// editing a tool, Figure 15's Check Out and Check In, and a tool's
/// details. The design shows the buttons; the dialogs use the console's
/// dialog and field styles.

/// Adds a tool, or edits [tool].
Future<void> showToolFormDialog(BuildContext context, {Tool? tool}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ToolFormDialog(tool: tool),
    );

class _ToolFormDialog extends ConsumerStatefulWidget {
  const _ToolFormDialog({this.tool});

  final Tool? tool;

  @override
  ConsumerState<_ToolFormDialog> createState() => _ToolFormDialogState();
}

class _ToolFormDialogState extends ConsumerState<_ToolFormDialog> {
  late final _code = TextEditingController(text: widget.tool?.toolCode);
  late final _name = TextEditingController(text: widget.tool?.name);
  late final _category = TextEditingController(text: widget.tool?.category);
  late final _location = TextEditingController(
    text: widget.tool?.storageLocation,
  );
  late final _qr = TextEditingController(text: widget.tool?.qrCode);
  late ItemCondition _condition = widget.tool?.condition ?? ItemCondition.good;
  String? _error;
  bool _busy = false;

  bool get _editing => widget.tool != null;

  @override
  void dispose() {
    for (final controller in [_code, _name, _category, _location, _qr]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final draft = ToolDraft(
      toolCode: _code.text,
      name: _name.text,
      condition: _condition,
      qrCode: _qr.text.trim().isEmpty
          ? ToolDraft.defaultQrCode(_code.text)
          : _qr.text,
      category: _category.text,
      storageLocation: _location.text,
    );
    if (draft.problem case final problem?) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(inventoryControllerProvider);
    final result = _editing
        ? await controller.updateTool(widget.tool!.id, draft)
        : await controller.createTool(draft);
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _editing
                  ? 'Saved ${draft.normalized().name}.'
                  : 'Added ${draft.normalized().name} to the tools.',
            ),
          ),
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
    final out = widget.tool?.status == ToolStatus.borrowed;
    Widget field(
      TextEditingController controller,
      String label, {
      String? hint,
      int? maxLength,
    }) => TextField(
      controller: controller,
      enabled: !_busy,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    );

    return AlertDialog(
      title: Text(_editing ? 'Edit tool' : 'Add new tool'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: field(
                      _code,
                      'Tool ID',
                      hint: 'TL-0824',
                      maxLength: ToolDraft.codeLimit,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: field(
                      _name,
                      'Tool name',
                      hint: 'e.g. DeWalt Impact Driver 20V',
                      maxLength: ToolDraft.nameLimit,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: field(
                      _category,
                      'Type (optional)',
                      hint: 'e.g. Power Tools',
                      maxLength: ToolDraft.shortLimit,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: field(
                      _location,
                      'Kept at (optional)',
                      maxLength: ToolDraft.nameLimit,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ItemCondition>(
                initialValue: _condition,
                decoration: InputDecoration(
                  labelText: 'Condition',
                  helperText: out
                      ? 'Out with a technician: Check In records the '
                            'condition it comes back in.'
                      : null,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final condition in ItemCondition.values)
                    DropdownMenuItem(
                      value: condition,
                      child: Text(condition.label),
                    ),
                ],
                onChanged: _busy || out
                    ? null
                    : (value) => setState(() => _condition = value!),
              ),
              const SizedBox(height: 12),
              field(
                _qr,
                _editing ? 'Code on its label' : 'Code on its label (optional)',
                hint: _editing ? null : 'TOOL- and the tool ID if empty',
                maxLength: ToolDraft.qrCodeLimit,
              ),
              if (_error case final message?) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  style: AppTextStyles.inventoryStatNote.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : (_editing ? 'Save' : 'Add tool')),
        ),
      ],
    );
  }
}

/// Figure 15's Check Out: lends [tool] to a technician, for one of their
/// open work orders or none.
Future<void> showCheckOutDialog(BuildContext context, Tool tool) =>
    showDialog<void>(
      context: context,
      builder: (_) => _CheckOutDialog(tool: tool),
    );

class _CheckOutDialog extends ConsumerStatefulWidget {
  const _CheckOutDialog({required this.tool});

  final Tool tool;

  @override
  ConsumerState<_CheckOutDialog> createState() => _CheckOutDialogState();
}

class _CheckOutDialogState extends ConsumerState<_CheckOutDialog> {
  AppUser? _technician;
  String? _workOrderId;
  DateTime? _returnBy;
  String? _error;
  bool _busy = false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnBy ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _returnBy = picked);
  }

  Future<void> _save() async {
    final technician = _technician;
    if (technician == null) {
      setState(() => _error = 'Pick the technician taking it.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final returnBy = _returnBy;
    final result = await ref
        .read(inventoryControllerProvider)
        .checkOut(
          toolId: widget.tool.id,
          technician: AuditActor(id: technician.id, name: technician.fullName),
          workOrderId: _workOrderId,
          // The end of the chosen day, as "due today" reads it.
          expectedReturnAt: returnBy == null
              ? null
              : DateTime(returnBy.year, returnBy.month, returnBy.day, 23, 59),
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Checked out ${widget.tool.name} to ${technician.fullName}.',
            ),
          ),
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
    final people = switch (ref.watch(personnelStreamProvider)) {
      AsyncData(value: Success(:final value)) => [
        for (final person in value)
          if (person.accountStatus == AccountStatus.active) person,
      ],
      _ => const <AppUser>[],
    };
    final technician = _technician;
    final orders = switch (ref.watch(workOrdersStreamProvider)) {
      AsyncData(value: Success(:final value)) when technician != null => [
        for (final order in value)
          if (MyWork.isOpen(order.status) &&
              order.assignedPersonnelIds.contains(technician.id))
            order,
      ],
      _ => const <WorkOrder>[],
    };

    return AlertDialog(
      title: Text('Check out ${widget.tool.name}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.tool.toolCode} · ${widget.tool.condition.label} '
              'condition. It is recorded against the technician until it '
              'is checked in.',
              style: AppTextStyles.inventoryStatNote,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AppUser>(
              initialValue: technician,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Technician',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final person in people)
                  DropdownMenuItem(value: person, child: Text(person.fullName)),
              ],
              onChanged: _busy
                  ? null
                  : (person) => setState(() {
                      _technician = person;
                      _workOrderId = null;
                    }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey(technician?.id),
              initialValue: _workOrderId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'For work order (optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(child: Text('None')),
                for (final order in orders)
                  DropdownMenuItem<String?>(
                    value: order.id,
                    child: Text(
                      '${DisplayId.workOrder(order.id)} · ${order.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy || technician == null
                  ? null
                  : (id) => setState(() => _workOrderId = id),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    _returnBy == null
                        ? 'Return by (optional)'
                        : 'Return by ${DateFormat('MMM d, y').format(_returnBy!)}',
                  ),
                ),
                if (_returnBy != null)
                  IconButton(
                    tooltip: 'No return date',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _returnBy = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
            if (_error case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: AppTextStyles.inventoryStatNote.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Check out'),
        ),
      ],
    );
  }
}

/// Figure 15's Check In: closes [loan], recording the condition the tool
/// came back in. A tool back in poor condition goes to repair.
Future<void> showCheckInDialog(
  BuildContext context, {
  required String toolName,
  required String loanId,
  required ItemCondition conditionOnBorrow,
  String? holderName,
}) => showDialog<void>(
  context: context,
  builder: (_) => _CheckInDialog(
    toolName: toolName,
    loanId: loanId,
    conditionOnBorrow: conditionOnBorrow,
    holderName: holderName,
  ),
);

class _CheckInDialog extends ConsumerStatefulWidget {
  const _CheckInDialog({
    required this.toolName,
    required this.loanId,
    required this.conditionOnBorrow,
    this.holderName,
  });

  final String toolName;
  final String loanId;
  final ItemCondition conditionOnBorrow;
  final String? holderName;

  @override
  ConsumerState<_CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends ConsumerState<_CheckInDialog> {
  late ItemCondition _condition = widget.conditionOnBorrow;
  final _notes = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final notes = _notes.text.trim();
    final result = await ref
        .read(inventoryControllerProvider)
        .checkIn(
          loanId: widget.loanId,
          condition: _condition,
          notes: notes.isEmpty ? null : notes,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _condition == ItemCondition.poor
                  ? 'Checked in ${widget.toolName}; it went to repair.'
                  : 'Checked in ${widget.toolName}.',
            ),
          ),
        );
      case Error(:final failure):
        setState(() {
          _busy = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Check in ${widget.toolName}'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.holderName == null ? 'It' : 'From ${widget.holderName}'}; '
            'it went out in ${widget.conditionOnBorrow.label.toLowerCase()} '
            'condition.',
            style: AppTextStyles.inventoryStatNote,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ItemCondition>(
            initialValue: _condition,
            decoration: const InputDecoration(
              labelText: 'Condition now',
              helperText: 'A tool back in poor condition goes to repair.',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final condition in ItemCondition.values)
                DropdownMenuItem(
                  value: condition,
                  child: Text(condition.label),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _condition = value!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            enabled: !_busy,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error case final message?) ...[
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.inventoryStatNote.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving…' : 'Check in'),
      ),
    ],
  );
}

/// A tool's details, its loans, and what can be done with it: edit, send
/// to repair or bring back, retire, print its label.
Future<void> showToolDetailsDialog(BuildContext context, String toolId) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ToolDetailsDialog(toolId: toolId),
    );

class _ToolDetailsDialog extends ConsumerWidget {
  const _ToolDetailsDialog({required this.toolId});

  final String toolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(toolProvider(toolId));
    return AlertDialog(
      title: switch (tool) {
        AsyncData(value: Success(:final value)) => Text(value.name),
        _ => const Text('Tool'),
      },
      content: SizedBox(
        width: 600,
        child: AsyncValueView<Tool>(
          value: tool,
          loadingHeight: 200,
          onRetry: () => ref.invalidate(toolProvider(toolId)),
          data: (tool) => _ToolDetails(tool: tool),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ToolDetails extends ConsumerWidget {
  const _ToolDetails({required this.tool});

  final Tool tool;

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    ToolStatus status,
    String done,
  ) async {
    final result = await ref
        .read(inventoryControllerProvider)
        .setToolStatus(tool.id, status);
    if (context.mounted) showInventoryOutcome(context, result, done);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(personnelNamesProvider);
    final loans = ref.watch(toolLoanHistoryProvider(tool.id));
    final when = DateFormat('MMM d, y h:mm a');

    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: AppTextStyles.inventoryCaption),
          ),
          Expanded(child: Text(value, style: AppTextStyles.inventoryCell)),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InventoryBadge.tool(tool.status),
            const SizedBox(width: 12),
            Text(tool.toolCode, style: AppTextStyles.inventoryCellStrong),
          ],
        ),
        const SizedBox(height: 16),
        fact('CONDITION', tool.condition.label),
        if (tool.category case final category?) fact('TYPE', category),
        if (tool.storageLocation case final location?)
          fact('KEPT AT', location),
        if (tool.currentHolderId case final holder?)
          fact('WITH', names[holder] ?? 'A technician'),
        fact('CODE ON LABEL', tool.qrCode),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => showToolFormDialog(context, tool: tool),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
            if (tool.status == ToolStatus.available)
              OutlinedButton.icon(
                onPressed: () => _move(
                  context,
                  ref,
                  ToolStatus.inRepair,
                  'Sent ${tool.name} to repair.',
                ),
                icon: const Icon(Icons.build_outlined, size: 18),
                label: const Text('Send to repair'),
              ),
            if (tool.status == ToolStatus.inRepair)
              OutlinedButton.icon(
                onPressed: () => _move(
                  context,
                  ref,
                  ToolStatus.available,
                  '${tool.name} is back on the shelf.',
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Back from repair'),
              ),
            if (tool.status == ToolStatus.available ||
                tool.status == ToolStatus.inRepair)
              OutlinedButton.icon(
                onPressed: () async {
                  final sure = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Retire ${tool.name}?'),
                      content: const Text(
                        'A retired tool cannot be checked out again. Its '
                        'loans stay in its history.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                          child: const Text('Retire'),
                        ),
                      ],
                    ),
                  );
                  if (sure == true && context.mounted) {
                    await _move(
                      context,
                      ref,
                      ToolStatus.retired,
                      'Retired ${tool.name}.',
                    );
                  }
                },
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Retire'),
              ),
            OutlinedButton.icon(
              onPressed: () => showQrLabelDialog(context, QrLabel.tool(tool)),
              icon: const Icon(Icons.qr_code_2_outlined, size: 18),
              label: const Text('QR label'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('LOANS', style: AppTextStyles.inventoryCaption),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: AsyncValueView<List<ToolLoan>>(
            value: loans,
            loadingHeight: 100,
            onRetry: () => ref.invalidate(toolLoanHistoryProvider(tool.id)),
            data: (loans) => loans.isEmpty
                ? const Text(
                    'Never checked out.',
                    style: AppTextStyles.inventoryStatNote,
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: loans.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final loan = loans[index];
                      final returned = loan.returnedAt;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          names[loan.borrowedBy] ?? 'A technician',
                          style: AppTextStyles.inventoryCellStrong,
                        ),
                        subtitle: Text(
                          'Out ${when.format(loan.borrowedAt.toLocal())}'
                          '${loan.workOrderId == null ? '' : ' for ${DisplayId.workOrder(loan.workOrderId!)}'}'
                          '${returned == null ? ' · not back yet' : ' · back ${when.format(returned.toLocal())}, ${loan.conditionOnReturn?.label.toLowerCase() ?? ''}'}'
                          '${loan.notes == null ? '' : ' · ${loan.notes}'}',
                          style: AppTextStyles.inventoryStatNote,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
