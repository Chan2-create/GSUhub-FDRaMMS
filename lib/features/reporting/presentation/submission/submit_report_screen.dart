import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/damage_categories.dart';
import '../../../../core/enums/priority_level.dart';
import '../../../../core/services/photo_picker_service.dart';
import '../../../../core/utils/display_id.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/filter_select.dart';
import '../../../../shells/requestor/requestor_header.dart';
import '../../../facilities/presentation/facility_directory.dart';
import '../my_reports/my_reports_providers.dart';
import 'qr_scanner_screen.dart';
import 'report_form_controller.dart';
import 'report_form_state.dart';
import 'widgets/form_parts.dart';
import 'widgets/location_card.dart';
import 'widgets/photo_evidence_card.dart';

/// Report Damage — the faculty and staff app's damage report form
/// (Figma `165:137`, Objective 3.C; manuscript §1.5, §3.4).
///
/// Layout, labels and colours are the design's. Where the design is
/// silent the additions are plain Material and flagged in the 3.C
/// report: the QR scan button (the design has none; its header button is
/// the bell), the camera-or-gallery sheet, the scanner and pin picker
/// screens, validation messages, upload progress and the confirmation.
class SubmitReportScreen extends ConsumerStatefulWidget {
  const SubmitReportScreen({super.key});

  @override
  ConsumerState<SubmitReportScreen> createState() => _SubmitReportScreenState();
}

class _SubmitReportScreenState extends ConsumerState<SubmitReportScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ReportFormController get _form =>
      ref.read(reportFormControllerProvider.notifier);

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addPhotos(PhotoSource source) async {
    final message = await _form.addPhotos(source);
    if (mounted && message != null) _say(message);
  }

  Future<void> _scanQr() async {
    final code = await ref.read(qrScanLauncherProvider)(context);
    if (!mounted || code == null) return;

    final result = await _form.applyQrCode(code);
    if (!mounted) return;
    _say(switch (result) {
      Success(value: final match) =>
        'Found ${match.asset == null ? '' : '${match.asset!.name} in '}'
            '${match.facility.buildingName}, '
            '${FacilityDirectory.roomLabelOf(match.facility)}.',
      Error(:final failure) => failure.message,
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await _form.submit();
    if (!mounted) return;

    final state = ref.read(reportFormControllerProvider);
    if (state.phase case SubmissionDone(:final reportId)) {
      await _confirm(reportId);
    } else if (state.showErrors && state.errors.isNotEmpty) {
      _say('Some details are missing. Check the highlighted fields.');
    }
  }

  /// Not in the design: the confirmation after filing. Plain Material,
  /// flagged. "Done" returns to the page the form was opened from (3.A),
  /// or starts a fresh form when there is none.
  Future<void> _confirm(String reportId) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Report submitted'),
        content: Text(
          'Report ${DisplayId.report(reportId)} has been sent to the General '
          'Services Unit for review.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // Home and My Reports read the requestor's reports once; the new one
    // should be there when they come back into view.
    ref.invalidate(myReportsProvider);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    _title.clear();
    _description.clear();
    ref.invalidate(reportFormControllerProvider);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(reportFormControllerProvider);
    final enabled = !form.isLocked;

    return PopScope(
      // Leaving mid-upload would abandon photos already sent.
      canPop: !form.phase.isBusy,
      child: Scaffold(
        backgroundColor: AppColors.mobilePageBackground,
        body: Column(
          children: [
            const RequestorHeader(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    _TitleRow(onScan: enabled ? _scanQr : null),
                    const SizedBox(height: 9),
                    _DetailsCard(
                      form: form,
                      title: _title,
                      enabled: enabled,
                      onTitle: _form.setTitle,
                      onType: _form.setDamageType,
                      onUrgency: _form.setUrgency,
                    ),
                    const SizedBox(height: 10),
                    _DescriptionField(
                      controller: _description,
                      enabled: enabled,
                      error: form.errorFor(ReportField.description),
                      onChanged: _form.setDescription,
                    ),
                    const SizedBox(height: 10),
                    PhotoEvidenceCard(
                      photos: form.photos,
                      enabled: enabled,
                      error: form.errorFor(ReportField.photos),
                      onAdd: _addPhotos,
                      onRemove: _form.removePhoto,
                    ),
                    const SizedBox(height: 9),
                    LocationCard(form: form),
                    if (form.phase case SubmissionFailed(:final message))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text(
                          message,
                          style: AppTextStyles.coordinates.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 25),
                    _SubmitButton(phase: form.phase, onPressed: _submit),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "← Report Damage", with the QR scan button at the right end — an
/// addition: the design has no scan button, and its header button is the
/// bell.
class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.onScan});

  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 0, 11, 0),
      child: Row(
        children: [
          // Opened from the home screen or the bottom bar, the arrow goes
          // back. Reached any other way there is nothing to go back to; the
          // arrow stays, as drawn, but idle.
          IconButton(
            tooltip: canGoBack ? 'Back' : null,
            onPressed: canGoBack
                ? () => Navigator.of(context).maybePop()
                : null,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            icon: SvgPicture.asset(
              'assets/icons/mobile_back.svg',
              width: 16,
              height: 16,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Report Damage',
              style: AppTextStyles.mobileScreenTitle,
            ),
          ),
          IconButton(
            tooltip: 'Scan a facility QR code',
            onPressed: onScan,
            icon: const Icon(
              Icons.qr_code_scanner,
              size: 22,
              color: AppColors.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// The first navy panel (`169:796`): title, damage type, urgency.
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.form,
    required this.title,
    required this.enabled,
    required this.onTitle,
    required this.onType,
    required this.onUrgency,
  });

  final ReportFormState form;
  final TextEditingController title;
  final bool enabled;
  final ValueChanged<String> onTitle;
  final ValueChanged<DamageCategory?> onType;
  final ValueChanged<PriorityLevel> onUrgency;

  @override
  Widget build(BuildContext context) => FormCard(
    color: AppColors.primary,
    shadow: true,
    padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 6),
          child: FormLabel(
            'Facility / issue title',
            color: AppColors.textOnDark,
          ),
        ),
        const SizedBox(height: 5),
        TintedTextBox(
          child: TextField(
            controller: title,
            enabled: enabled,
            onChanged: onTitle,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            style: AppTextStyles.formTitleInput,
            cursorColor: AppColors.textOnDark,
            decoration: const InputDecoration(
              hintText: 'e.g., Broken Ceiling Fan',
              hintStyle: AppTextStyles.formTitlePlaceholder,
              border: InputBorder.none,
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18.5,
              ),
            ),
          ),
        ),
        FieldError(
          form.errorFor(ReportField.title),
          color: AppColors.errorOnNavy,
        ),
        const SizedBox(height: 19),
        FieldPair(
          left: LabelledField(
            label: 'Damage type',
            labelColor: AppColors.textOnDark,
            errorColor: AppColors.errorOnNavy,
            field: FilterSelect<DamageCategory>(
              style: FilterSelectStyle.form,
              placeholder: 'Select Type',
              enabled: enabled,
              value: form.damageType,
              options: [
                // A suggestion, so it can be taken back.
                const FilterOption(value: null, label: 'Not sure'),
                for (final category in DamageCategory.values)
                  FilterOption(value: category, label: category.label),
              ],
              onChanged: onType,
            ),
          ),
          right: LabelledField(
            label: 'Urgency level',
            labelColor: AppColors.textOnDark,
            errorColor: AppColors.errorOnNavy,
            error: form.errorFor(ReportField.urgency),
            field: FilterSelect<PriorityLevel>(
              style: FilterSelectStyle.form,
              placeholder: 'Select Level',
              enabled: enabled,
              value: form.urgency,
              // The design's dot (`169:701`), shown once a level is chosen.
              leading: form.urgency == null
                  ? null
                  : Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.accentOlive,
                        shape: BoxShape.circle,
                      ),
                    ),
              options: [
                for (final level in PriorityLevel.values)
                  FilterOption(value: level, label: level.title),
              ],
              onChanged: (level) {
                if (level != null) onUrgency(level);
              },
            ),
          ),
        ),
      ],
    ),
  );
}

/// DAMAGE DESCRIPTION (`169:705`, `169:707`), on the page between panels.
class _DescriptionField extends StatelessWidget {
  const _DescriptionField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.error,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(17, 0, 18, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormLabel('Damage description', color: AppColors.textStrong),
        const SizedBox(height: 5),
        TintedTextBox(
          padding: const EdgeInsets.all(17),
          child: TextField(
            controller: controller,
            enabled: enabled,
            onChanged: onChanged,
            minLines: 4,
            maxLines: 10,
            maxLength: 2000,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: AppTextStyles.formTextArea,
            decoration: InputDecoration(
              hintText: 'Describe the facility damage in detail...',
              hintStyle: AppTextStyles.formTextArea.copyWith(
                color: AppColors.formPlaceholder,
              ),
              border: InputBorder.none,
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            ),
          ),
        ),
        FieldError(error, color: AppColors.error),
      ],
    ),
  );
}

/// Submit Report (`169:790`). While sending it carries the progress:
/// which photo is going up, filled left to right — an addition, flagged.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.phase, required this.onPressed});

  final SubmissionPhase phase;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final busy = phase.isBusy;
    final fraction = switch (phase) {
      SubmissionUploading(:final fraction) => fraction,
      SubmissionSaving() || SubmissionDone() => 1.0,
      _ => 0.0,
    };
    final label = switch (phase) {
      SubmissionUploading(:final current, :final total) =>
        'Uploading photo $current of $total…',
      SubmissionSaving() => 'Submitting…',
      SubmissionDone() => 'Submitted',
      _ => 'Submit Report',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 0, 15, 0),
      child: Semantics(
        button: true,
        enabled: !busy,
        label: label,
        excludeSemantics: true,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [
              BoxShadow(
                color: AppColors.submitGlow,
                offset: Offset(0, 8),
                blurRadius: 8,
              ),
            ],
          ),
          child: Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: busy || phase is SubmissionDone ? null : onPressed,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (busy)
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction,
                      child: const ColoredBox(color: Color(0x33FFFFFF)),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (busy)
                          const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textOnDark,
                            ),
                          )
                        else
                          SvgPicture.asset(
                            'assets/icons/report_send.svg',
                            width: 19,
                            height: 16,
                          ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            style: AppTextStyles.submitLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
