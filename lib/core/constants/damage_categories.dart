/// The seven predefined facility-damage categories used by GSUhub's
/// rule-based classification engine (manuscript §1.5 Scope, §2.2, §3.4
/// Table 3.3 "Rule-Based Classification and Maintenance Personnel
/// Assignment Rules").
///
/// A report whose description does not match any category's keywords is
/// routed to the authorized GSU Administrator for manual classification —
/// that fallback and the keyword-matching logic itself belong to Objective
/// 1.3 (rule-based classification), not this scaffolding pass. The
/// [sampleKeywords] listed here are the reference keywords from Table 3.3,
/// kept alongside the category for traceability; the live, admin-editable
/// keyword dictionary is built in 1.3.
enum DamageCategory {
  electrical(
    label: 'Electrical',
    assignedPersonnelLabel: 'Electrician',
    sampleKeywords: [
      'power outage',
      'exposed wire',
      'short circuit',
      'faulty outlet',
    ],
  ),
  plumbing(
    label: 'Plumbing',
    assignedPersonnelLabel: 'Plumbing Personnel',
    sampleKeywords: [
      'leaking pipe',
      'clogged drain',
      'broken faucet',
      'flooding',
    ],
  ),
  structural(
    label: 'Structural',
    assignedPersonnelLabel: 'Structural Maintenance Personnel',
    sampleKeywords: [
      'cracked wall',
      'damaged ceiling',
      'broken floor',
      'structural damage',
    ],
  ),
  carpentry(
    label: 'Carpentry',
    assignedPersonnelLabel: 'Structural Maintenance Personnel',
    sampleKeywords: [
      'broken door',
      'damaged window',
      'broken chair',
      'broken cabinet',
    ],
  ),
  airConditioning(
    label: 'Air Conditioning',
    assignedPersonnelLabel: 'Aircon Technician',
    sampleKeywords: [
      'aircon not cooling',
      'leaking aircon',
      'ventilation issue',
    ],
  ),
  cleaningAndSanitation(
    label: 'Cleaning and Sanitation',
    assignedPersonnelLabel: 'Janitorial Personnel',
    sampleKeywords: [
      'waste buildup',
      'dirty area',
      'foul odor',
      'sanitation concern',
    ],
  ),
  generalMaintenance(
    label: 'General Maintenance',
    assignedPersonnelLabel: 'General Maintenance Personnel',
    sampleKeywords: <String>[],
  );

  const DamageCategory({
    required this.label,
    required this.assignedPersonnelLabel,
    required this.sampleKeywords,
  });

  /// Human-readable category name, as shown in UI (e.g. report filters).
  final String label;

  /// Default maintenance personnel role assigned when a report is
  /// classified into this category (Table 3.3).
  final String assignedPersonnelLabel;

  /// Reference keywords from Table 3.3. `generalMaintenance` has none
  /// listed in the manuscript — it is the catch-all category.
  final List<String> sampleKeywords;

  /// The value persisted on the `damage_reports/{id}.category` field.
  String get id => name;

  static DamageCategory fromId(String id) => DamageCategory.values.firstWhere(
    (category) => category.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'Unknown DamageCategory'),
  );
}
