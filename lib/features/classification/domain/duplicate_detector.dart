import 'package:flutter/foundation.dart';

import '../../../core/enums/report_status.dart';
import '../../reporting/data/models/damage_report.dart';
import '../data/models/duplicate_detection_config.dart';
import 'keyword_classifier.dart';

/// Another report that may describe the same damage (Objective 4.C).
@immutable
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.report,
    required this.similarity,
    required this.sameCategory,
    required this.apart,
  });

  final DamageReport report;

  /// How alike the two descriptions are, 0–1: the share of the shorter
  /// one's key words that the other also uses.
  final double similarity;

  /// Both reports carry the same damage type.
  final bool sameCategory;

  /// How far apart the two were filed.
  final Duration apart;

  @override
  String toString() =>
      'DuplicateCandidate(${report.id}, similarity: '
      '${similarity.toStringAsFixed(2)}, sameCategory: $sameCategory)';
}

/// Which report of a flagged pair is kept, and which is merged into it.
@immutable
class MergePlan {
  const MergePlan({required this.parent, required this.duplicate});

  /// The report kept: it carries the work, and its requestor's report goes
  /// on as before.
  final DamageReport parent;

  /// The report closed as a duplicate of [parent].
  final DamageReport duplicate;
}

/// Flags reports that may describe the same damage (manuscript §3.4,
/// "Duplicate Report Detection Rules"; Objective 4.C).
///
/// §3.4 lists five things to compare — the QR code or facility, the
/// facility location, the damage category, how alike the descriptions are,
/// and the time between them — and says "reports submitted for the same
/// facility within a defined time period are flagged as potential
/// duplicates". How they combine is DERIVED: two reports are flagged when
/// all of these hold:
///
/// 1. both are still open and neither has been merged;
/// 2. an administrator has not already ruled them separate;
/// 3. they are at the same place — the same facility, or the same stated
///    location (whichever [DuplicateDetectionConfig] enables);
/// 4. they were filed within the configured window of each other; and
/// 5. they share a damage type, or their descriptions are at least
///    [DuplicateDetectionConfig.descriptionSimilarityThreshold] alike and
///    share at least [minSharedWords] key words.
///
/// Detection only flags. An administrator merges, dismisses, or keeps them
/// as separate requests (§1.5); nothing here changes a report.
class DuplicateDetector {
  const DuplicateDetector(this.config);

  final DuplicateDetectionConfig config;

  /// Key words two reports of different (or unknown) damage types must
  /// share before their wording alone flags them. One shared word is not
  /// evidence: "Broken window" and "Broken light" are half alike by
  /// [overlap], and two different jobs. DERIVED, like the measure itself.
  static const int minSharedWords = 2;

  /// Whether [report] can be flagged at all: still open, and not already
  /// merged into another.
  static bool isFlaggable(DamageReport report) =>
      report.status.isOpen && report.duplicateOf == null;

  /// The possible duplicates of [report] among [others], most alike first.
  List<DuplicateCandidate> candidatesFor(
    DamageReport report,
    Iterable<DamageReport> others,
  ) => _candidatesFor(report, others.toList(), {});

  /// Every report in [reports] that has possible duplicates, with them —
  /// for marking the reports table in one pass.
  Map<String, List<DuplicateCandidate>> flagsFor(List<DamageReport> reports) {
    final open = reports.where(isFlaggable).toList();
    final words = <String, Set<String>>{};
    final flags = <String, List<DuplicateCandidate>>{};
    for (final report in open) {
      final candidates = _candidatesFor(report, open, words);
      if (candidates.isNotEmpty) flags[report.id] = candidates;
    }
    return flags;
  }

  List<DuplicateCandidate> _candidatesFor(
    DamageReport report,
    List<DamageReport> others,
    Map<String, Set<String>> words,
  ) {
    if (!config.enabled || !isFlaggable(report)) return const [];
    final mine = _wordsOf(report, words);

    final found = <DuplicateCandidate>[];
    for (final other in others) {
      if (other.id == report.id || !isFlaggable(other)) continue;
      if (report.dismissedDuplicateIds.contains(other.id) ||
          other.dismissedDuplicateIds.contains(report.id)) {
        continue;
      }
      if (!_samePlace(report, other)) continue;

      final apart = report.submittedAt.difference(other.submittedAt).abs();
      if (apart > config.timeWindow) continue;

      final sameCategory =
          report.category != null && report.category == other.category;
      final theirs = _wordsOf(other, words);
      final alike = overlap(mine, theirs);
      final related =
          (config.matchOnCategory && sameCategory) ||
          (alike >= config.descriptionSimilarityThreshold &&
              mine.intersection(theirs).length >= minSharedWords);
      if (!related) continue;

      found.add(
        DuplicateCandidate(
          report: other,
          similarity: alike,
          sameCategory: sameCategory,
          apart: apart,
        ),
      );
    }

    found.sort((a, b) {
      final bySimilarity = b.similarity.compareTo(a.similarity);
      return bySimilarity != 0 ? bySimilarity : a.apart.compareTo(b.apart);
    });
    return found;
  }

  bool _samePlace(DamageReport a, DamageReport b) {
    final checks = [
      if (config.matchOnFacilityIdentifier)
        a.facilityId != null && a.facilityId == b.facilityId,
      if (config.matchOnLocation)
        _sameText(a.locationDescription, b.locationDescription),
    ];
    // Either one identifies the place. With both off, place is not
    // compared at all — as the configuration then asks.
    return checks.isEmpty || checks.contains(true);
  }

  static bool _sameText(String? a, String? b) {
    final left = KeywordClassifier.normalize(a ?? '');
    return left.isNotEmpty && left == KeywordClassifier.normalize(b ?? '');
  }

  /// A report's key words, less the words of its own location: the place
  /// is compared on its own, so "Room 101" in two descriptions must not
  /// make two different problems in that room look alike.
  static Set<String> _wordsOf(
    DamageReport report,
    Map<String, Set<String>> cache,
  ) => cache.putIfAbsent(report.id, () {
    final place = keyWords(
      '${report.facilityName ?? ''} ${report.locationDescription ?? ''}',
    );
    return keyWords(
      KeywordClassifier.textOf(
        title: report.title,
        description: report.description,
      ),
    ).difference(place);
  });

  /// How alike two texts are, 0–1: the share of the shorter one's key
  /// words that the other also uses.
  static double similarity(String a, String b) =>
      overlap(keyWords(a), keyWords(b));

  /// The share of the smaller set that the larger also holds; 0 when
  /// either is empty.
  static double overlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final shared = a.intersection(b).length;
    return shared / (a.length < b.length ? a.length : b.length);
  }

  /// The words of [text] that say something: lower case, without common
  /// words ("the", "and", "was") or words shorter than three letters, and
  /// with plain endings trimmed so "leaks", "leaking" and "leaked" count
  /// as one word. Numbers stay — "Room 101" and "2nd floor" matter.
  static Set<String> keyWords(String text) {
    final normalized = KeywordClassifier.normalize(text);
    if (normalized.isEmpty) return {};
    return {
      for (final word in normalized.split(' '))
        if (word.contains(_digit) ||
            (word.length >= 3 && !_commonWords.contains(word)))
          _stem(word),
    };
  }

  static final RegExp _digit = RegExp('[0-9]');

  /// Trims a plain English ending. Deliberately crude — the same crude
  /// rule applied to both texts is all a comparison needs.
  static String _stem(String word) {
    var stem = word;
    if (stem.length > 3 && stem.endsWith('s') && !stem.endsWith('ss')) {
      stem = stem.substring(0, stem.length - 1);
    }
    if (stem.length > 5 && stem.endsWith('ing')) {
      return stem.substring(0, stem.length - 3);
    }
    if (stem.length > 4 && (stem.endsWith('ed') || stem.endsWith('ly'))) {
      return stem.substring(0, stem.length - 2);
    }
    return stem;
  }

  static const Set<String> _commonWords = {
    'the',
    'and',
    'but',
    'for',
    'from',
    'with',
    'without',
    'are',
    'was',
    'were',
    'been',
    'being',
    'its',
    'this',
    'that',
    'these',
    'those',
    'there',
    'here',
    'has',
    'have',
    'had',
    'does',
    'did',
    'not',
    'can',
    'could',
    'will',
    'would',
    'should',
    'may',
    'might',
    'must',
    'very',
    'too',
    'also',
    'just',
    'when',
    'while',
    'where',
    'which',
    'who',
    'what',
    'how',
    'why',
    'all',
    'any',
    'some',
    'more',
    'most',
    'other',
    'into',
    'onto',
    'over',
    'under',
    'about',
    'again',
    'still',
    'now',
    'then',
    'than',
    'our',
    'your',
    'their',
    'his',
    'her',
    'they',
    'them',
    'you',
    'she',
    'please',
    'already',
    'since',
    'because',
    'like',
    'get',
    'got',
    'one',
    'out',
    'off',
    'yet',
  };

  /// Which of [a] and [b] to keep if they are merged, or null when neither
  /// can be merged — only a report still awaiting review can be closed as
  /// a duplicate, so one already approved or being worked always survives.
  /// When both could go, the earlier report is kept: it was there first.
  static MergePlan? mergePlanFor(DamageReport a, DamageReport b) {
    final aCanGo = canBeMerged(a);
    final bCanGo = canBeMerged(b);
    if (aCanGo && bCanGo) {
      return a.submittedAt.isAfter(b.submittedAt)
          ? MergePlan(parent: b, duplicate: a)
          : MergePlan(parent: a, duplicate: b);
    }
    if (bCanGo) return MergePlan(parent: a, duplicate: b);
    if (aCanGo) return MergePlan(parent: b, duplicate: a);
    return null;
  }

  /// Whether [report] can be closed as a duplicate: still awaiting review,
  /// with no work order.
  static bool canBeMerged(DamageReport report) =>
      report.duplicateOf == null &&
      report.workOrderId == null &&
      report.status.canTransitionTo(ReportStatus.merged);
}
