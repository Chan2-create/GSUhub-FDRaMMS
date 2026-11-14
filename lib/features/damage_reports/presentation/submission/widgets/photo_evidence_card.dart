import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_text_styles.dart';
import '../../../../../core/services/photo_picker_service.dart';
import '../report_form_state.dart';
import 'form_parts.dart';

/// PHOTO EVIDENCE (Figma `169:799`): the drop zone that opens the camera or
/// gallery, and a thumbnail per chosen photo with its remove badge.
class PhotoEvidenceCard extends StatelessWidget {
  const PhotoEvidenceCard({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
    required this.enabled,
    super.key,
    this.error,
  });

  final List<DraftPhoto> photos;
  final ValueChanged<PhotoSource> onAdd;
  final ValueChanged<int> onRemove;
  final bool enabled;
  final String? error;

  Future<void> _chooseSource(BuildContext context) async {
    // Not in the design: which of the prompt's two halves ("take photo or
    // upload from gallery") to use. A plain Material sheet, flagged.
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) onAdd(source);
  }

  @override
  Widget build(BuildContext context) => FormCard(
    color: AppColors.primary,
    padding: const EdgeInsets.fromLTRB(12, 23, 12, 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: FormLabel('Photo evidence', color: AppColors.textOnDark),
        ),
        const SizedBox(height: 13),
        _DropZone(onTap: enabled ? () => _chooseSource(context) : null),
        FieldError(error, color: AppColors.errorOnNavy),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final photo in photos)
                _Thumbnail(
                  key: ValueKey(photo.id),
                  photo: photo,
                  onRemove: enabled ? () => onRemove(photo.id) : null,
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add photo',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: const _DashedBorderPainter(
            color: AppColors.accentGold,
            radius: 16,
            strokeWidth: 2,
          ),
          child: Container(
            height: 129,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.dropZoneFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.cameraCircle,
                    shape: BoxShape.circle,
                  ),
                  child: SvgPicture.asset(
                    'assets/icons/report_camera.svg',
                    width: 25,
                    height: 22.5,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tap to take photo or upload from gallery',
                  style: AppTextStyles.dropZonePrompt,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.photo, required this.onRemove, super.key});

  final DraftPhoto photo;
  final VoidCallback? onRemove;

  static const double _size = 80;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _size,
          height: _size,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderStrong),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.memory(
              photo.photo.bytes,
              fit: BoxFit.cover,
              // Decoded at thumbnail size, not the photo's own 1920px.
              cacheWidth: 240,
              gaplessPlayback: true,
              semanticLabel: 'Photo ${photo.id + 1}',
              errorBuilder: (_, _, _) => const ColoredBox(
                color: AppColors.surfaceMuted,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
        if (onRemove != null)
          // The badge is 12px (`169:723`); the tap target around it is not.
          Positioned(
            top: -6,
            right: -8,
            child: Semantics(
              button: true,
              label: 'Remove photo ${photo.id + 1}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 9, 10, 9),
                  child: SvgPicture.asset(
                    'assets/icons/photo_remove.svg',
                    width: 16.1667,
                    height: 16.1667,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The drop zone's 2px dashed gold outline (`border-dashed`). Flutter's
/// borders are solid only, so the dashes are cut from the outline path.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  static const double _dash = 6;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius - inset),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final PathMetric metric in outline.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += _dash + _gap) {
        canvas.drawPath(metric.extractPath(start, start + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color ||
      radius != oldDelegate.radius ||
      strokeWidth != oldDelegate.strokeWidth;
}
