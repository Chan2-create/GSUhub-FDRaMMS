import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/constants/damage_categories.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_card.dart';
import '../../settings/presentation/widgets/settings_parts.dart';
import '../data/models/classification_rules_config.dart';
import '../domain/keyword_classifier.dart';
import 'classification_providers.dart';
import 'keyword_draft.dart';
import 'keyword_settings_controller.dart';

/// The Settings page's keyword dictionary (Objective 4.A): the keywords
/// each damage type is recognised by, which an administrator adds and
/// removes, with a box to try a description against them before saving.
///
/// Not in the Figma file; built in the console's existing style (Chris,
/// 2026-10-12). The Keywords tab since 2026-11-14.
class KeywordSettingsSection extends ConsumerWidget {
  const KeywordSettingsSection({super.key, this.onUnsavedChanged});

  /// Told whether the tab holds edits that are not saved.
  final ValueChanged<bool>? onUnsavedChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncValueView<ClassificationRulesConfig>(
        value: ref.watch(keywordRulesProvider),
        onRetry: () => ref.invalidate(keywordRulesProvider),
        data: (config) =>
            _KeywordEditor(config: config, onUnsavedChanged: onUnsavedChanged),
      );
}

class _KeywordEditor extends ConsumerStatefulWidget {
  const _KeywordEditor({required this.config, this.onUnsavedChanged});

  /// The saved dictionary, or Table 3.3's when none is saved.
  final ClassificationRulesConfig config;

  final ValueChanged<bool>? onUnsavedChanged;

  @override
  ConsumerState<_KeywordEditor> createState() => _KeywordEditorState();
}

class _KeywordEditorState extends ConsumerState<_KeywordEditor>
    with ReportsUnsaved {
  late KeywordDraft _draft = KeywordDraft.of(widget.config);
  bool _saving = false;

  bool get _isManuscriptList =>
      widget.config.updatedBy == manuscriptDefaultsAuthor;

  bool get _hasChanges => !_draft.sameKeywordsAs(widget.config);

  @override
  void didUpdateWidget(covariant _KeywordEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A list was saved, from this page or another. Show it, unless there
    // are edits here it did not include: those stay, and saving them
    // replaces it.
    if (_draft.sameKeywordsAs(oldWidget.config)) {
      _draft = KeywordDraft.of(widget.config);
    }
  }

  void _edit(KeywordDraft draft) => setState(() => _draft = draft);

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await ref
        .read(keywordSettingsControllerProvider)
        .save(_draft);
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    result.fold(
      (_) => messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Keywords saved. Reports filed from now on are classified '
            'with them.',
          ),
        ),
      ),
      (failure) => messenger.showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    reportUnsaved(widget.onUnsavedChanged, unsaved: _hasChanges);

    final editor = SectionCard(
      title: 'Classification keywords',
      subtitle:
          'A new report\'s title and description are checked against these '
          'keywords, and it gets the damage type with the most matches. A '
          'report that matches none, or two types equally, is left for an '
          'administrator to classify.',
      trailing: Padding(
        padding: const EdgeInsets.only(left: 24),
        child: Text(
          _isManuscriptList
              ? 'Not saved yet'
              : 'Last saved ${DateFormat('d MMM y, h:mm a').format(widget.config.updatedAt.toLocal())}',
          style: AppTextStyles.bodySmall,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isManuscriptList) ...[
            const SettingsNotice(
              'These are the default keywords. The app uses them until a '
              'list is saved here; save once to keep your changes.',
            ),
            const SizedBox(height: 20),
          ],
          for (final category in DamageCategory.values) ...[
            if (category != DamageCategory.values.first)
              const Divider(height: 28),
            _CategoryKeywords(
              category: category,
              draft: _draft,
              enabled: !_saving,
              onChanged: _edit,
            ),
          ],
          SettingsSaveBar(
            state: _hasChanges
                ? SettingsSaveState.unsaved
                : _isManuscriptList
                ? SettingsSaveState.defaults
                : SettingsSaveState.saved,
            unsavedNote:
                'Reports are classified with the saved list until you save.',
            canDiscard: _hasChanges && !_saving,
            onDiscard: () => _edit(KeywordDraft.of(widget.config)),
            canSave: (_hasChanges || _isManuscriptList) && !_saving,
            onSave: _save,
            saving: _saving,
          ),
        ],
      ),
    );
    final tryIt = _TryDescription(classifier: _draft.classifier);

    // Side by side wherever they fit — a 1366-pixel laptop screen leaves
    // 997 beside the sidebar — so a description can be tried while the
    // keywords are edited.
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 960
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: editor),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: tryIt),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [editor, const SizedBox(height: 24), tryIt],
            ),
    );
  }
}

/// One damage type's keywords, each removable, with Add keyword after the
/// last. The box to type one in opens on Add keyword and stays open for
/// the next: seven empty boxes down the page, one per type, were most of
/// what made it long.
class _CategoryKeywords extends StatefulWidget {
  const _CategoryKeywords({
    required this.category,
    required this.draft,
    required this.enabled,
    required this.onChanged,
  });

  final DamageCategory category;
  final KeywordDraft draft;
  final bool enabled;
  final ValueChanged<KeywordDraft> onChanged;

  @override
  State<_CategoryKeywords> createState() => _CategoryKeywordsState();
}

class _CategoryKeywordsState extends State<_CategoryKeywords> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  String? _problem;
  bool _adding = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open() {
    setState(() => _adding = true);
    // The box is built by this frame; the cursor goes in it after.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _close() => setState(() {
    _adding = false;
    _problem = null;
    _input.clear();
  });

  void _add() {
    final problem = widget.draft.problemWith(widget.category, _input.text);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    widget.onChanged(widget.draft.adding(widget.category, _input.text));
    _input.clear();
    setState(() => _problem = null);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final keywords = widget.draft.keywordsOf(category);

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(category.label, style: AppTextStyles.fieldValue),
        const SizedBox(height: 2),
        Text(
          keywords.length == 1 ? '1 keyword' : '${keywords.length} keywords',
          style: AppTextStyles.bodySmall,
        ),
      ],
    );
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (keywords.isEmpty) ...[
          const Text(
            'No keywords. A report gets this type only when an '
            'administrator chooses it.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final keyword in keywords)
              InputChip(
                label: Text(keyword),
                onDeleted: widget.enabled
                    ? () => widget.onChanged(
                        widget.draft.removing(category, keyword),
                      )
                    : null,
                deleteButtonTooltipMessage: 'Remove "$keyword"',
              ),
            if (!_adding)
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Add keyword'),
                tooltip: 'Add a keyword to ${category.label}',
                onPressed: widget.enabled ? _open : null,
              ),
          ],
        ),
        if (_adding) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    maxLength: KeywordDraft.maxLength,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    onChanged: (_) {
                      if (_problem != null) setState(() => _problem = null);
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Add a keyword or phrase',
                      counterText: '',
                      errorText: _problem,
                      errorMaxLines: 3,
                      border: const OutlineInputBorder(),
                    ),
                    style: AppTextStyles.inputText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Tooltip(
                  message: 'Add to ${category.label}',
                  child: TextButton.icon(
                    onPressed: widget.enabled ? _add : null,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: IconButton(
                  tooltip: 'Done adding to ${category.label}',
                  onPressed: _close,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    // On a phone the damage type goes above its keywords: beside them,
    // its column left the keywords and the Add field no room at 320.
    if (Breakpoints.isCompact(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [heading, const SizedBox(height: 10), editor],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 160, child: heading),
        const SizedBox(width: 16),
        Expanded(child: editor),
      ],
    );
  }
}

/// A box to type a description into and see how the keywords on the page
/// (unsaved edits included) classify it.
class _TryDescription extends StatefulWidget {
  const _TryDescription({required this.classifier});

  final KeywordClassifier classifier;

  @override
  State<_TryDescription> createState() => _TryDescriptionState();
}

class _TryDescriptionState extends State<_TryDescription> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Try a description',
    subtitle:
        'Type what a requestor might write to see how the keywords classify '
        'it, unsaved changes included.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          style: AppTextStyles.inputText,
          decoration: const InputDecoration(
            hintText:
                'e.g. Water is leaking from the pipe under the sink and '
                'the floor is flooding.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _TryResult(
          text: _text.text,
          result: widget.classifier.classify(_text.text),
        ),
      ],
    ),
  );
}

class _TryResult extends StatelessWidget {
  const _TryResult({required this.text, required this.result});

  final String text;
  final ClassificationResult result;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const Text(
        'The result appears here as you type.',
        style: AppTextStyles.bodySmall,
      );
    }
    final found = [
      for (final category in DamageCategory.values)
        if (result.keywordsFor(category) case final keywords
            when keywords.isNotEmpty)
          '${category.label}: ${keywords.map((k) => '"$k"').join(', ')}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (result) {
          ClassificationResult(category: final category?) =>
            'Classified as ${category.label}.',
          ClassificationResult(isTie: true) =>
            'Two damage types match equally, so an administrator would '
                'classify it.',
          _ => 'No keyword matched, so an administrator would classify it.',
        }, style: AppTextStyles.fieldValue),
        if (found.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Keywords found', style: AppTextStyles.fieldLabel),
          const SizedBox(height: 4),
          for (final line in found) Text(line, style: AppTextStyles.bodySmall),
        ],
      ],
    );
  }
}
