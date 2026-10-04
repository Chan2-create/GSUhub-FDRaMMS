import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../data/models/service_feedback.dart';
import '../rating_controller.dart';
import 'star_rating.dart';

/// A given rating: the three dimensions with their stars and words, and
/// the comment. Shared by the Ratings screen and the report detail page.
class RatingSummary extends StatelessWidget {
  const RatingSummary({required this.rating, super.key});

  final ServiceFeedback rating;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (RatingDimension.responseTime, rating.responseTimeRating),
      (RatingDimension.serviceQuality, rating.serviceQualityRating),
      (RatingDimension.overallSatisfaction, rating.overallSatisfactionRating),
    ];
    final comments = rating.comments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (dimension, stars) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    dimension.label,
                    style: AppTextStyles.ratingDimension,
                  ),
                ),
                StarRating(value: stars, label: dimension.label, size: 20),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    ratingWord(stars),
                    style: AppTextStyles.ratingMeta.copyWith(
                      color: AppColors.trackingAccentText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (comments != null) ...[
          const SizedBox(height: 4),
          Text('"$comments"', style: AppTextStyles.trackingNote),
        ],
      ],
    );
  }
}
