import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_card.dart';
import '../data/models/holiday.dart';
import 'holiday_providers.dart';
import 'widgets/settings_parts.dart';

/// Settings → Holidays (2026-11-26): the days no work is scheduled on,
/// besides Saturdays and Sundays. The Philippine holidays move every year
/// (Holy Week, the Eid holidays, the ones proclaimed each year), so the
/// administrator keeps them here; nothing is entered for them. Every
/// scheduling date picker leaves them out, and the database refuses them.
///
/// Saved entry by entry, as Departments is.
class HolidaysSettingsSection extends ConsumerStatefulWidget {
  const HolidaysSettingsSection({super.key});

  @override
  ConsumerState<HolidaysSettingsSection> createState() =>
      _HolidaysSettingsSectionState();
}

class _HolidaysSettingsSectionState
    extends ConsumerState<HolidaysSettingsSection> {
  final _name = TextEditingController();
  DateTime? _day;
  bool _adding = false;

  static final DateFormat _shown = DateFormat('EEE, MMM d, y');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      // Any day: a holiday is listed whatever day of the week it falls on.
      initialDate: _day ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 3, 12, 31),
      helpText: 'Holiday on',
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    final day = _day;
    final messenger = ScaffoldMessenger.of(context);
    if (day == null || name.isEmpty) {
      _showFailure(messenger, 'Choose the date and name the holiday.');
      return;
    }
    if (_adding) return;
    setState(() => _adding = true);
    final result = await ref.read(holidayRepositoryProvider).add(day, name);
    if (!mounted) return;
    setState(() => _adding = false);
    result.fold((_) {
      _name.clear();
      setState(() => _day = null);
      messenger.showSnackBar(
        SnackBar(content: Text('Added $name on ${_shown.format(day)}.')),
      );
    }, (failure) => _showFailure(messenger, failure.message));
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Holidays',
    subtitle:
        'Days no work is scheduled on, besides Saturdays and Sundays. The '
        'date pickers for schedules, target dates and task due dates leave '
        'them out. Philippine holidays change every year: add each year\'s '
        'here.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Add one',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('new-holiday-day'),
                onPressed: _adding ? null : _pickDay,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  _day == null ? 'Choose date' : _shown.format(_day!),
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  key: const ValueKey('new-holiday-name'),
                  controller: _name,
                  enabled: !_adding,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Bonifacio Day',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              FilledButton(
                key: const ValueKey('add-holiday'),
                onPressed: _adding ? null : _add,
                child: Text(_adding ? 'Adding…' : 'Add'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          title: 'On the list',
          description:
              'Removing one makes the day a working day again, if it is a '
              'weekday. Past holidays stay listed until removed.',
          child: AsyncValueView<List<Holiday>>(
            value: ref.watch(holidaysProvider),
            onRetry: () => ref.invalidate(holidaysProvider),
            isEmpty: (list) => list.isEmpty,
            emptyMessage:
                'No holidays yet. Until some are added, only Saturdays and '
                'Sundays are left out of the date pickers.',
            data: (list) => Column(
              children: [
                for (final holiday in list) _HolidayRow(holiday: holiday),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

void _showFailure(ScaffoldMessengerState messenger, String message) =>
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );

class _HolidayRow extends ConsumerStatefulWidget {
  const _HolidayRow({required this.holiday});

  final Holiday holiday;

  @override
  ConsumerState<_HolidayRow> createState() => _HolidayRowState();
}

class _HolidayRowState extends ConsumerState<_HolidayRow> {
  bool _busy = false;

  static final DateFormat _shown = DateFormat('EEE, MMM d, y');

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final result = await ref
        .read(holidayRepositoryProvider)
        .remove(widget.holiday.day);
    if (mounted) setState(() => _busy = false);
    result.fold(
      (_) => messenger.showSnackBar(
        SnackBar(content: Text('Removed ${widget.holiday.name}.')),
      ),
      (failure) => _showFailure(messenger, failure.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final holiday = widget.holiday;
    final past = holiday.day.isBefore(DateUtils.dateOnly(DateTime.now()));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              _shown.format(holiday.day),
              style: AppTextStyles.fieldValue.copyWith(
                color: past ? AppColors.textFaint : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              holiday.name,
              style: AppTextStyles.fieldValue.copyWith(
                color: past ? AppColors.textFaint : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove ${holiday.name}',
            onPressed: _busy ? null : _remove,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}
