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
import '../../settings/presentation/widgets/settings_parts.dart';
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
  const PrioritySettingsSection({super.key, this.onUnsavedChanged});

  /// Told whether the tab holds edits that are not saved.
  final ValueChanged<bool>? onUnsavedChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncValueView<PrioritizationConfig>(
        value: ref.watch(prioritizationConfigProvider),
        onRetry: () => ref.invalidate(prioritizationConfigProvider),
        data: (config) =>
            _PriorityEditor(config: config, onUnsavedChanged: onUnsavedChanged),
      );
}

class _PriorityEditor extends ConsumerStatefulWidget {
  const _PriorityEditor({required this.config, this.onUnsavedChanged});

  final PrioritizationConfig config;

  final ValueChanged<bool>? onUnsavedChanged;

  @override
  ConsumerState<_PriorityEditor> createState() => _PriorityEditorState();
}

class _PriorityEditorState extends ConsumerState<_PriorityEditor>
    with ReportsUnsaved {
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
    // Edits that do not read as a configuration yet are unsaved too.
    reportUnsaved(widget.onUnsavedChanged, unsaved: changed || problem != null);

    final usesFormula = _scheme == PrioritizationScheme.decimalWeights;

    return SectionCard(
      title: 'Priority scoring',
      subtitle:
          'Each report is rated 1 to 4 on four criteria. The weights turn '
          'the ratings into a score, and the score into a recommended '
          'priority. The administrator still sets the official priority.',
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
          // What the settings below add up to, first: the effect of a
          // change shows here before it is saved.
          if (problem != null)
            _Outcome(
              color: AppColors.statusPendingBackground,
              child: Text(
                problem,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.statusPendingForeground,
                ),
              ),
            )
          else if (sample != null && sampleScore != null)
            _Outcome(
              color: AppColors.surfaceSunken,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Example: a report rated Severity 3, Safety risk 3, '
                    'Frequency 2, Location importance 2 would score '
                    '${sampleScore.toStringAsFixed(2)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  PriorityChip(level: sample.levelFor(sampleScore)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          SettingsGroup(
            title: 'Weights',
            description:
                'How much each criterion counts. The study gives two sets; '
                'both are kept, and the score uses the one chosen here.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioGroup<PrioritizationScheme>(
                  groupValue: _scheme,
                  onChanged: (scheme) {
                    if (scheme != null && !_saving) {
                      setState(() => _scheme = scheme);
                    }
                  },
                  // The card is a coloured box: the tiles paint on a
                  // Material of their own.
                  child: const Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        RadioListTile(
                          value: PrioritizationScheme.decimalWeights,
                          title: Text('Formula weights'),
                          subtitle: Text(
                            'From the priority formula. The default.',
                          ),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                        RadioListTile(
                          value: PrioritizationScheme.integerWeights,
                          title: Text('Table weights'),
                          subtitle: Text('From the criteria table.'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Only the set in use: the other is kept as it was, and
                // shows when it is chosen.
                _FieldRow(
                  fields: {
                    for (final MapEntry(:key, :value)
                        in (usesFormula ? _decimal : _integer).entries)
                      _criterionLabel(key): value,
                  },
                  enabled: !_saving,
                ),
              ],
            ),
          ),
          const Divider(height: 40),
          SettingsGroup(
            title: 'Priority levels',
            description: 'The lowest score that earns each level.',
            child: _FieldRow(
              fields: {
                for (final MapEntry(:key, :value) in _bands.entries)
                  key.label: value,
              },
              enabled: !_saving,
            ),
          ),
          const Divider(height: 40),
          SettingsGroup(
            title: 'Frequency',
            description:
                'Similar reports are counted over a number of days, and the '
                'count suggests the Frequency rating: how many reports rate '
                'it 2, 3 and 4.',
            child: _FieldRow(
              fields: {
                'Days': _window,
                for (final (index, field) in _counts.indexed)
                  'Rating ${index + 2} from': field,
              },
              enabled: !_saving,
            ),
          ),
          SettingsSaveBar(
            state: changed || problem != null
                ? SettingsSaveState.unsaved
                : _isDefault
                ? SettingsSaveState.defaults
                : SettingsSaveState.saved,
            unsavedNote:
                'Reports are scored with the saved settings until you save.',
            canDiscard: (changed || problem != null) && !_saving,
            onDiscard: () => setState(() {
              _dispose();
              _load(widget.config);
            }),
            canSave: (changed || _isDefault) && problem == null && !_saving,
            onSave: _save,
            saving: _saving,
          ),
        ],
      ),
    );
  }
}

/// The tinted line at the top of the priority tab: the example score, or
/// what is wrong with the numbers.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
}

// --------------------------------------------------------------- duplicates

/// The Settings page's duplicate detection (Objective 7.A): whether
/// reports are compared, what they are compared on, how alike two
/// descriptions must be, and how far apart in time (manuscript §3.4,
/// "Duplicate Report Detection Rules"). No design covers it.
class DuplicateSettingsSection extends ConsumerWidget {
  const DuplicateSettingsSection({super.key, this.onUnsavedChanged});

  /// Told whether the tab holds edits that are not saved.
  final ValueChanged<bool>? onUnsavedChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncValueView<DuplicateDetectionConfig>(
        value: ref.watch(duplicateDetectionConfigProvider),
        onRetry: () => ref.invalidate(duplicateDetectionConfigProvider),
        data: (config) => _DuplicateEditor(
          config: config,
          onUnsavedChanged: onUnsavedChanged,
        ),
      );
}

class _DuplicateEditor extends ConsumerStatefulWidget {
  const _DuplicateEditor({required this.config, this.onUnsavedChanged});

  final DuplicateDetectionConfig config;

  final ValueChanged<bool>? onUnsavedChanged;

  @override
  ConsumerState<_DuplicateEditor> createState() => _DuplicateEditorState();
}

class _DuplicateEditorState extends ConsumerState<_DuplicateEditor>
    with ReportsUnsaved {
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
    final comparing = enabled && _draft.enabled;
    final alike = (_draft.descriptionSimilarityThreshold * 100).round();
    reportUnsaved(
      widget.onUnsavedChanged,
      unsaved: changed || _hoursProblem != null,
    );

    /// One thing two reports are compared on: a tick box before its name.
    Widget compare(
      String label,
      bool value,
      DuplicateDetectionConfig Function(bool on) set,
    ) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: Text(label),
      value: value,
      onChanged: comparing
          ? (on) => setState(() => _draft = set(on ?? false))
          : null,
    );

    return SectionCard(
      title: 'Duplicate detection',
      subtitle:
          'Reports filed for the same place close together in time are '
          'compared, and a likely repeat is flagged for an administrator '
          'to merge or keep separate.',
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
              subtitle: const Text(
                'Off, no report is compared and nothing below applies.',
              ),
              value: _draft.enabled,
              onChanged: enabled
                  ? (value) =>
                        setState(() => _draft = _draft.copyWith(enabled: value))
                  : null,
            ),
            const Divider(height: 32),
            SettingsGroup(
              title: 'Compare on',
              description:
                  'Two reports are a possible duplicate when these match.',
              child: Column(
                children: [
                  compare(
                    'Compare the facility or asset (QR code)',
                    _draft.matchOnFacilityIdentifier,
                    (on) => _draft.copyWith(matchOnFacilityIdentifier: on),
                  ),
                  compare(
                    'Compare the stated location',
                    _draft.matchOnLocation,
                    (on) => _draft.copyWith(matchOnLocation: on),
                  ),
                  compare(
                    'Compare the damage type',
                    _draft.matchOnCategory,
                    (on) => _draft.copyWith(matchOnCategory: on),
                  ),
                ],
              ),
            ),
            const Divider(height: 32),
            SettingsGroup(
              title: 'How alike the descriptions must be',
              description:
                  'The share of words two descriptions have in common.',
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _draft.descriptionSimilarityThreshold,
                      divisions: 20,
                      label: '$alike%',
                      onChanged: comparing
                          ? (value) => setState(
                              () => _draft = _draft.copyWith(
                                descriptionSimilarityThreshold: value,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '$alike%',
                      textAlign: TextAlign.end,
                      style: AppTextStyles.fieldValue,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 32),
            SettingsGroup(
              title: 'Time window',
              description:
                  'Reports filed further apart than this are not compared.',
              child: SizedBox(
                width: 200,
                child: TextField(
                  controller: _hours,
                  enabled: comparing,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Window, in hours',
                    suffixText: 'hours',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: _hoursProblem,
                    errorMaxLines: 3,
                  ),
                ),
              ),
            ),
            SettingsSaveBar(
              state: changed || _hoursProblem != null
                  ? SettingsSaveState.unsaved
                  : _isDefault
                  ? SettingsSaveState.defaults
                  : SettingsSaveState.saved,
              unsavedNote:
                  'Reports are compared with the saved settings until you '
                  'save.',
              canDiscard: (changed || _hoursProblem != null) && !_saving,
              onDiscard: () => setState(() {
                _draft = widget.config;
                _hours.text = '${widget.config.timeWindowHours}';
              }),
              canSave:
                  (changed || _isDefault) && _hoursProblem == null && !_saving,
              onSave: _save,
              saving: _saving,
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

/// A row of small number fields, each named on its box.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.fields, required this.enabled});

  final Map<String, TextEditingController> fields;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      for (final MapEntry(:key, :value) in fields.entries)
        SizedBox(
          width: 150,
          child: TextField(
            controller: value,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: key,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
    ],
  );
}
