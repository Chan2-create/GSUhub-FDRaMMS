import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/di/repository_providers.dart';
import '../../../core/enums/priority_level.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/result.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/priority_chip.dart';
import '../../../core/widgets/section_card.dart';
import '../../audit/presentation/current_actor_provider.dart';
import '../data/models/duplicate_detection_config.dart';
import '../data/models/prioritization_config.dart';
import '../domain/priority_scorer.dart';
import 'classification_providers.dart';

/// Saves the scoring and duplicate settings edited on the Settings page
/// (Objective 7.A). The database checks them again before they are kept
/// (supabase/migrations/*_config_validation.sql).
class ScoringSettingsController {
  const ScoringSettingsController(this._ref);

  final Ref _ref;

  Future<Result<void>> savePrioritization(PrioritizationConfig config) => _save(
    (actor) => _ref
        .read(configRepositoryProvider)
        .updatePrioritization(
          config.copyWith(updatedAt: clock.now().toUtc(), updatedBy: actor),
        ),
  );

  Future<Result<void>> saveDuplicateDetection(
    DuplicateDetectionConfig config,
  ) => _save(
    (actor) => _ref
        .read(configRepositoryProvider)
        .updateDuplicateDetection(
          config.copyWith(updatedAt: clock.now().toUtc(), updatedBy: actor),
        ),
  );

  Future<Result<void>> _save(
    Future<Result<void>> Function(String actor) save,
  ) async {
    final actor = await _ref.read(currentActorProvider.future);
    if (actor == null) {
      return const Result.failure(
        PermissionFailure('Your session has expired. Please sign in again.'),
      );
    }
    return save(actor.id);
  }
}

final scoringSettingsControllerProvider = Provider(
  ScoringSettingsController.new,
);

String _criterionLabel(PrioritizationCriterion criterion) =>
    switch (criterion) {
      PrioritizationCriterion.severity => 'Severity',
      PrioritizationCriterion.safetyRisk => 'Safety risk',
      PrioritizationCriterion.frequency => 'Frequency',
      PrioritizationCriterion.locationImportance => 'Location importance',
    };

/// "0.4", not "0.40000000000000002"; "3", not "3.0".
String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : NumberFormat('0.0###').format(value);

String _savedLine(DateTime updatedAt, String updatedBy) =>
    updatedBy == manuscriptDefaultsAuthor
    ? 'Not saved yet'
    : 'Last saved ${DateFormat('d MMM y, h:mm a').format(updatedAt.toLocal())}';

// ---------------------------------------------------------------- priority

/// The Settings page's priority scoring (Objective 7.A): which weights the
/// score uses, the weights themselves, Table 3.5's bands and the Frequency
/// hint.
///
/// Configurable on purpose, and flagged: the manuscript gives two sets of
/// weights that disagree (Table 3.2's 3/4/2/3 and the §3.4 formula's
/// 0.40/0.30/0.20/0.10). Chris chose the formula's (2026-10-12), which is
/// the default; both are kept, so either can be used without a code change.
/// No design covers it: built in the console's existing style.
class PrioritySettingsSection extends ConsumerWidget {
  const PrioritySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncValueView<PrioritizationConfig>(
        value: ref.watch(prioritizationConfigProvider),
        onRetry: () => ref.invalidate(prioritizationConfigProvider),
        data: (config) => _PriorityEditor(config: config),
      );
}

class _PriorityEditor extends ConsumerStatefulWidget {
  const _PriorityEditor({required this.config});

  final PrioritizationConfig config;

  @override
  ConsumerState<_PriorityEditor> createState() => _PriorityEditorState();
}

class _PriorityEditorState extends ConsumerState<_PriorityEditor> {
  /// Table 3.5's order: Critical first. The enum runs the other way.
  static const List<PriorityLevel> _bandOrder = [
    PriorityLevel.critical,
    PriorityLevel.high,
    PriorityLevel.medium,
    PriorityLevel.low,
  ];

  late PrioritizationScheme _scheme;
  late Map<PrioritizationCriterion, TextEditingController> _decimal;
  late Map<PrioritizationCriterion, TextEditingController> _integer;
  late Map<PriorityLevel, TextEditingController> _bands;
  late TextEditingController _window;
  late List<TextEditingController> _counts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load(widget.config);
  }

  @override
  void didUpdateWidget(covariant _PriorityEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Saved, here or elsewhere: show it, unless there are edits here it
    // did not include.
    if (widget.config != oldWidget.config && _draft() == oldWidget.config) {
      _dispose();
      _load(widget.config);
    }
  }

  void _load(PrioritizationConfig config) {
    TextEditingController field(double value) =>
        TextEditingController(text: _number(value))..addListener(_changed);
    _scheme = config.activeScheme;
    _decimal = {
      for (final c in PrioritizationCriterion.values)
        c: field(config.decimalWeights[c]!),
    };
    _integer = {
      for (final c in PrioritizationCriterion.values)
        c: field(config.integerWeights[c]!),
    };
    _bands = {
      for (final level in _bandOrder) level: field(config.thresholds[level]!),
    };
    _window = field(config.frequencyWindowDays.toDouble());
    _counts = [
      for (final count in config.frequencyBands) field(count.toDouble()),
    ];
  }

  void _changed() => setState(() {});

  void _dispose() {
    for (final controller in [
      ..._decimal.values,
      ..._integer.values,
      ..._bands.values,
      _window,
      ..._counts,
    ]) {
      controller.dispose();
    }
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  static double? _read(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  /// What is wrong with the fields, as the database would say it, or null.
  String? get _problem {
    for (final weights in [_decimal, _integer]) {
      var positive = false;
      for (final field in weights.values) {
        final value = _read(field);
        if (value == null || value < 0 || value > 100) {
          return 'Every weight must be a number from 0 to 100.';
        }
        positive = positive || value > 0;
      }
      if (!positive) return 'At least one weight must be above 0.';
    }
    double? previous;
    for (final level in _bandOrder) {
      final bound = _read(_bands[level]!);
      if (bound == null || bound < 1 || bound > 4) {
        return 'Each score band must start between 1.00 and 4.00.';
      }
      if (previous != null && bound >= previous) {
        return 'The score bands must fall from Critical to Low.';
      }
      previous = bound;
    }
    final window = _read(_window);
    if (window == null ||
        window < 1 ||
        window > 365 ||
        window != window.roundToDouble()) {
      return 'The frequency window must be a whole number of days from 1 to '
          '365.';
    }
    var last = 1.0;
    for (final field in _counts) {
      final count = _read(field);
      if (count == null || count <= last || count != count.roundToDouble()) {
        return 'The report counts for Frequency must be whole numbers that '
            'rise with the rating, starting above 1.';
      }
      last = count;
    }
    return null;
  }

  /// The fields as a configuration, or null while one does not read.
  PrioritizationConfig? _draft() {
    if (_problem != null) return null;
    return widget.config.copyWith(
      activeScheme: _scheme,
      decimalWeights: {
        for (final MapEntry(:key, :value) in _decimal.entries)
          key: _read(value)!,
      },
      integerWeights: {
        for (final MapEntry(:key, :value) in _integer.entries)
          key: _read(value)!,
      },
      thresholds: {
        for (final MapEntry(:key, :value) in _bands.entries) key: _read(value)!,
      },
      frequencyWindowDays: _read(_window)!.toInt(),
      frequencyBands: [for (final field in _counts) _read(field)!.toInt()],
    );
  }

  bool get _isDefault => widget.config.updatedBy == manuscriptDefaultsAuthor;

  Future<void> _save() async {
    final draft = _draft();
    if (draft == null) return;
    setState(() => _saving = true);
    final result = await ref
        .read(scoringSettingsControllerProvider)
        .savePrioritization(draft);
    if (!mounted) return;
    setState(() => _saving = false);
    _tell(
      context,
      result,
      'Priority scoring saved. Reports rated from now on are scored with '
      'it; scores already recorded stay as they were.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final draft = _draft();
    final changed = draft != null && draft != widget.config;
    // A sample, so the effect of a change can be seen before saving:
    // Severity 3, Safety risk 3, Frequency 2, Location importance 2.
    final sample = draft == null ? null : PriorityScorer(draft);
    const sampleRatings = {
      PrioritizationCriterion.severity: 3,
      PrioritizationCriterion.safetyRisk: 3,
      PrioritizationCriterion.frequency: 2,
      PrioritizationCriterion.locationImportance: 2,
    };
    final sampleScore = sample?.score(sampleRatings);

    return SectionCard(
      title: 'Priority scoring',
      subtitle:
          'The recommended priority is Σ weight × rating ÷ Σ weights, each '
          'criterion rated 1 to 4 (manuscript §3.4, Tables 3.4 and 3.5). '
          'The administrator still sets the official priority (§1.5).',
      trailing: Padding(
        padding: const EdgeInsets.only(left: 24),
        child: Text(
          _savedLine(widget.config.updatedAt, widget.config.updatedBy),
          style: AppTextStyles.bodySmall,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Notice(
            'The manuscript gives two sets of weights that disagree: Table '
            '3.2 lists Severity 3, Safety risk 4, Frequency 2, Location '
            'importance 3; the §3.4 formula uses 0.40, 0.30, 0.20 and 0.10. '
            'The formula\'s are the default (chosen 2026-10-12). Both are '
            'kept here; pick the one the score uses once the manuscript is '
            'settled.',
          ),
          const SizedBox(height: 20),
          RadioGroup<PrioritizationScheme>(
            groupValue: _scheme,
            onChanged: (scheme) {
              if (scheme != null && !_saving) setState(() => _scheme = scheme);
            },
            // The card is a coloured box: the tiles paint on a Material
            // of their own.
            child: const Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  RadioListTile(
                    value: PrioritizationScheme.decimalWeights,
                    title: Text('The §3.4 formula\'s weights'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile(
                    value: PrioritizationScheme.integerWeights,
                    title: Text('Table 3.2\'s weights'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _FieldRow(
            label: 'Formula weights',
            fields: {
              for (final MapEntry(:key, :value) in _decimal.entries)
                _criterionLabel(key): value,
            },
            enabled: !_saving,
          ),
          const SizedBox(height: 16),
          _FieldRow(
            label: 'Table 3.2 weights',
            fields: {
              for (final MapEntry(:key, :value) in _integer.entries)
                _criterionLabel(key): value,
            },
            enabled: !_saving,
          ),
          const SizedBox(height: 16),
          _FieldRow(
            label: 'Score bands: a level starts at (Table 3.5)',
            fields: {
              for (final MapEntry(:key, :value) in _bands.entries)
                key.label: value,
            },
            enabled: !_saving,
          ),
          const SizedBox(height: 16),
          _FieldRow(
            label:
                'Frequency hint: similar reports counted over this many '
                'days, and the counts that rate it 2, 3 and 4',
            fields: {
              'Days': _window,
              for (final (index, field) in _counts.indexed)
                'Rating ${index + 2} from': field,
            },
            enabled: !_saving,
          ),
          const SizedBox(height: 16),
          if (problem != null)
            Text(
              problem,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            )
          else if (sample != null && sampleScore != null)
            Row(
              children: [
                Flexible(
                  child: Text(
                    'A report rated Severity 3, Safety risk 3, Frequency 2, '
                    'Location importance 2 would score '
                    '${sampleScore.toStringAsFixed(2)}:',
                    style: AppTextStyles.bodySmall,
                  ),
                ),
                const SizedBox(width: 8),
                PriorityChip(level: sample.levelFor(sampleScore)),
              ],
            ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          _SaveRow(
            status: changed
                ? 'Unsaved changes. Reports are scored with the saved '
                      'settings until you save.'
                : _isDefault
                ? 'The manuscript\'s settings apply until these are saved.'
                : 'All changes saved.',
            canDiscard: (changed || problem != null) && !_saving,
            onDiscard: () => setState(() {
              _dispose();
              _load(widget.config);
            }),
            canSave: (changed || _isDefault) && problem == null && !_saving,
            onSave: _save,
            saving: _saving,
            saveLabel: 'Save priority scoring',
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- duplicates

/// The Settings page's duplicate detection (Objective 7.A): whether
/// reports are compared, what they are compared on, how alike two
/// descriptions must be, and how far apart in time (manuscript §3.4,
/// "Duplicate Report Detection Rules"). No design covers it.
class DuplicateSettingsSection extends ConsumerWidget {
  const DuplicateSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncValueView<DuplicateDetectionConfig>(
        value: ref.watch(duplicateDetectionConfigProvider),
        onRetry: () => ref.invalidate(duplicateDetectionConfigProvider),
        data: (config) => _DuplicateEditor(config: config),
      );
}

class _DuplicateEditor extends ConsumerStatefulWidget {
  const _DuplicateEditor({required this.config});

  final DuplicateDetectionConfig config;

  @override
  ConsumerState<_DuplicateEditor> createState() => _DuplicateEditorState();
}

class _DuplicateEditorState extends ConsumerState<_DuplicateEditor> {
  late DuplicateDetectionConfig _draft = widget.config;
  late final TextEditingController _hours = TextEditingController(
    text: '${widget.config.timeWindowHours}',
  )..addListener(_hoursChanged);
  bool _saving = false;
  String? _hoursProblem;

  @override
  void didUpdateWidget(covariant _DuplicateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config != oldWidget.config && _draft == oldWidget.config) {
      _draft = widget.config;
      _hours.text = '${widget.config.timeWindowHours}';
    }
  }

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  void _hoursChanged() {
    final hours = int.tryParse(_hours.text.trim());
    setState(() {
      if (hours == null || hours < 1 || hours > 2160) {
        _hoursProblem =
            'The window must be a whole number of hours from 1 to 2160 '
            '(90 days).';
      } else {
        _hoursProblem = null;
        _draft = _draft.copyWith(timeWindowHours: hours);
      }
    });
  }

  bool get _isDefault => widget.config.updatedBy == manuscriptDefaultsAuthor;

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await ref
        .read(scoringSettingsControllerProvider)
        .saveDuplicateDetection(_draft);
    if (!mounted) return;
    setState(() => _saving = false);
    _tell(
      context,
      result,
      'Duplicate detection saved. Reports are compared with it from now '
      'on.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final changed = _draft != widget.config;
    final enabled = !_saving;

    return SectionCard(
      title: 'Duplicate detection',
      subtitle:
          'Reports filed for the same place within the window are compared, '
          'and a possible duplicate is flagged for an administrator to '
          'merge or keep separate (manuscript §3.4).',
      trailing: Padding(
        padding: const EdgeInsets.only(left: 24),
        child: Text(
          _savedLine(widget.config.updatedAt, widget.config.updatedBy),
          style: AppTextStyles.bodySmall,
        ),
      ),
      // The card is a coloured box: the tiles paint on a Material of their
      // own.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Flag possible duplicates'),
              value: _draft.enabled,
              onChanged: enabled
                  ? (value) =>
                        setState(() => _draft = _draft.copyWith(enabled: value))
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compare the facility or asset (QR code)'),
              value: _draft.matchOnFacilityIdentifier,
              onChanged: enabled && _draft.enabled
                  ? (value) => setState(
                      () => _draft = _draft.copyWith(
                        matchOnFacilityIdentifier: value ?? false,
                      ),
                    )
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compare the stated location'),
              value: _draft.matchOnLocation,
              onChanged: enabled && _draft.enabled
                  ? (value) => setState(
                      () => _draft = _draft.copyWith(
                        matchOnLocation: value ?? false,
                      ),
                    )
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compare the damage type'),
              value: _draft.matchOnCategory,
              onChanged: enabled && _draft.enabled
                  ? (value) => setState(
                      () => _draft = _draft.copyWith(
                        matchOnCategory: value ?? false,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              'How alike two descriptions must be: '
              '${(_draft.descriptionSimilarityThreshold * 100).round()}% of '
              'their words in common',
              style: AppTextStyles.bodySmall,
            ),
            Slider(
              value: _draft.descriptionSimilarityThreshold,
              divisions: 20,
              label:
                  '${(_draft.descriptionSimilarityThreshold * 100).round()}%',
              onChanged: enabled && _draft.enabled
                  ? (value) => setState(
                      () => _draft = _draft.copyWith(
                        descriptionSimilarityThreshold: value,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _hours,
                enabled: enabled && _draft.enabled,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Window, in hours',
                  border: const OutlineInputBorder(),
                  errorText: _hoursProblem,
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            _SaveRow(
              status: changed
                  ? 'Unsaved changes.'
                  : _isDefault
                  ? 'The default settings apply until these are saved.'
                  : 'All changes saved.',
              canDiscard: (changed || _hoursProblem != null) && !_saving,
              onDiscard: () => setState(() {
                _draft = widget.config;
                _hours.text = '${widget.config.timeWindowHours}';
              }),
              canSave:
                  (changed || _isDefault) && _hoursProblem == null && !_saving,
              onSave: _save,
              saving: _saving,
              saveLabel: 'Save duplicate detection',
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- shared

/// Shows [result]'s failure, or [success].
void _tell(BuildContext context, Result<void> result, String success) {
  final messenger = ScaffoldMessenger.of(context);
  result.fold(
    (_) => messenger.showSnackBar(SnackBar(content: Text(success))),
    (failure) => messenger.showSnackBar(
      SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ),
    ),
  );
}

/// A labelled row of small number fields.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.fields,
    required this.enabled,
  });

  final String label;
  final Map<String, TextEditingController> fields;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.fieldLabel),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final MapEntry(:key, :value) in fields.entries)
            SizedBox(
              width: 150,
              child: TextField(
                controller: value,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: key,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

class _SaveRow extends StatelessWidget {
  const _SaveRow({
    required this.status,
    required this.canDiscard,
    required this.onDiscard,
    required this.canSave,
    required this.onSave,
    required this.saving,
    required this.saveLabel,
  });

  final String status;
  final bool canDiscard;
  final VoidCallback onDiscard;
  final bool canSave;
  final VoidCallback onSave;
  final bool saving;
  final String saveLabel;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 16,
    runSpacing: 12,
    children: [
      Text(status, style: AppTextStyles.bodySmall),
      // A Wrap, so the two buttons stack in a narrow window.
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: canDiscard ? onDiscard : null,
            child: const Text('Discard changes'),
          ),
          FilledButton(
            onPressed: canSave ? onSave : null,
            child: Text(saving ? 'Saving…' : saveLabel),
          ),
        ],
      ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: AppTextStyles.bodySmall)),
        ],
      ),
    ),
  );
}
