/// Top-level Firestore collection names used across GSUhub.
///
/// Centralizing these as constants avoids magic strings scattered across
/// data sources and keeps collection renames a one-line change. Names are
/// derived from the entities described in the manuscript (facility damage
/// reports, work orders, inventory/tool tracking, feedback, etc.) — see
/// docs/architecture_decisions.md for the mapping from manuscript entity to
/// collection name.
///
/// This file intentionally declares paths only, not document schemas or
/// data models; those are built alongside each owning feature module.
abstract final class FirestorePaths {
  /// User accounts for all three roles (requestor, maintenance personnel,
  /// admin) with role/permission fields (manuscript §1.5 "User-account
  /// management").
  static const String users = 'users';

  /// Registered campus buildings/rooms eligible for QR code identification
  /// and geo-tagged reporting (manuscript §1.7 "QR Code Identification").
  static const String facilities = 'facilities';

  /// Registered equipment/assets tracked independently of their containing
  /// facility, also QR-code identifiable.
  static const String assets = 'assets';

  /// Facility damage reports submitted by requestors (manuscript §1.7
  /// "Facility Damage Report").
  static const String damageReports = 'damage_reports';

  /// Work orders generated from approved damage reports and assigned to
  /// maintenance personnel (manuscript §1.7 "Work Order").
  static const String workOrders = 'work_orders';

  /// Individual tasks under a work order, for personnel daily task
  /// management (manuscript §1.2 objectives, mobile personnel app).
  static const String tasks = 'tasks';

  /// Completion notes and photo documentation submitted per work order
  /// (manuscript §1.5 "accomplishment reporting").
  static const String accomplishmentReports = 'accomplishment_reports';

  /// Maintenance materials/parts catalog with quantity, unit, storage
  /// location (manuscript §3.4 "Inventory and Material Consumption
  /// Tracking").
  static const String inventoryItems = 'inventory_items';

  /// Issuance/consumption/replenishment ledger for [inventoryItems].
  static const String inventoryTransactions = 'inventory_transactions';

  /// Reusable maintenance tools and equipment, distinct from consumable
  /// [inventoryItems].
  static const String tools = 'tools';

  /// Borrow/return records for [tools], including condition and personnel
  /// accountability.
  static const String toolLoans = 'tool_loans';

  /// Post-service feedback and ratings (manuscript §1.7 "Feedback and
  /// Rating System").
  static const String feedback = 'feedback';

  /// In-app notification records backing Firebase Cloud Messaging pushes.
  static const String notifications = 'notifications';

  /// Append-only activity log for auditability (report submissions, task
  /// assignments, status changes, completions).
  static const String auditLogs = 'audit_logs';

  /// System-wide configuration documents: classification keyword
  /// dictionaries, prioritization weights, and low-stock thresholds — kept
  /// as data rather than hardcoded, per manuscript §3.4.
  static const String config = 'config';
}
