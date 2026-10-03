// Security rules tests for firebase/firestore.rules.
//
// Verifies the permission matrix derived from manuscript §3.4's per-role
// Requirements Specification (see docs/data_dictionary.md). Rules are the
// only thing standing between one requestor and every other requestor's
// reports, so "we think they're right" is not good enough.
//
// Run with:
//     npm run test:rules
//
// This uses @firebase/rules-unit-testing rather than `flutter test`.
// Firebase's Flutter plugins need a platform channel and cannot initialize
// in the Dart-only test VM, so rules simply cannot be exercised from
// `flutter test`. This is also the approach Firebase documents: it runs in
// Node against the emulator, needs no device, and can bypass rules to set
// up fixtures.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';
import { GeoPoint } from 'firebase/firestore';

const PROJECT_ID = 'gsuhub-rules-test';

const ADMIN_UID = 'admin-uid';
const FACULTY_UID = 'faculty-uid';
const PERSONNEL_UID = 'personnel-uid';
const OTHER_FACULTY_UID = 'other-faculty-uid';
const INACTIVE_UID = 'inactive-uid';
const PENDING_UID = 'pending-uid';
const SIGNUP_UID = 'signup-uid';
const SIGNUP_EMAIL = 'liza.tan@dorsu.edu.ph';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync('firebase/firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });

  // Fixtures are written with rules disabled — these are preconditions,
  // not operations under test.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await db.doc(`users/${ADMIN_UID}`).set({
      fullName: 'Ramon Dela Cruz',
      email: 'admin@dorsu.edu.ph',
      role: 'admin',
      accountStatus: 'active',
      activeTaskCount: 0,
    });
    await db.doc(`users/${FACULTY_UID}`).set({
      fullName: 'Maria Santos',
      email: 'faculty@dorsu.edu.ph',
      role: 'requestor',
      accountStatus: 'active',
      activeTaskCount: 0,
    });
    await db.doc(`users/${OTHER_FACULTY_UID}`).set({
      fullName: 'Other Faculty',
      email: 'other@dorsu.edu.ph',
      role: 'requestor',
      accountStatus: 'active',
      activeTaskCount: 0,
    });
    await db.doc(`users/${PERSONNEL_UID}`).set({
      fullName: 'Marcus Wright',
      email: 'personnel@dorsu.edu.ph',
      role: 'maintenancePersonnel',
      accountStatus: 'active',
      specialization: 'electrical',
      availability: 'available',
      activeTaskCount: 0,
    });
    // §1.5 requires accounts to be deactivatable; a deactivated account
    // must lose access even though its credentials still authenticate.
    await db.doc(`users/${INACTIVE_UID}`).set({
      fullName: 'Former Staff',
      email: 'former@dorsu.edu.ph',
      role: 'requestor',
      accountStatus: 'inactive',
      activeTaskCount: 0,
    });
    // Signed themselves up from the faculty and staff app and not yet
    // approved (3.A).
    await db.doc(`users/${PENDING_UID}`).set({
      fullName: 'Ana Request',
      email: 'ana.request@dorsu.edu.ph',
      role: 'requestor',
      accountStatus: 'pending',
      activeTaskCount: 0,
    });

    await db.doc('facilities/fac-engineering').set({
      name: 'Engineering Building',
      buildingName: 'Engineering Building',
      qrCode: 'FAC-ENG',
      isActive: true,
    });

    await db.doc('damage_reports/rep-faculty').set({
      reporterId: FACULTY_UID,
      reporterName: 'Maria Santos',
      title: 'Broken Ceiling Fan',
      description: 'Fan wobbles badly.',
      requestorPriority: 'high',
      status: 'submitted',
    });
    await db.doc('damage_reports/rep-other').set({
      reporterId: OTHER_FACULTY_UID,
      reporterName: 'Other Faculty',
      title: "Someone else's report",
      description: 'Not visible to the first requestor.',
      requestorPriority: 'low',
      status: 'submitted',
    });

    await db.doc('work_orders/wo-assigned').set({
      reportIds: ['rep-faculty'],
      title: 'Repair ceiling fan',
      description: 'Replace bearing.',
      category: 'electrical',
      priority: 'high',
      status: 'pending',
      assignedPersonnelIds: [PERSONNEL_UID],
      createdBy: ADMIN_UID,
    });
    await db.doc('work_orders/wo-unassigned').set({
      reportIds: ['rep-other'],
      title: 'Someone else’s work order',
      description: 'Assigned to nobody.',
      category: 'plumbing',
      priority: 'low',
      status: 'pending',
      assignedPersonnelIds: [],
      createdBy: ADMIN_UID,
    });

    await db.doc('inventory_items/inv-led').set({
      name: 'LED Bulbs',
      category: 'Electrical',
      quantityAvailable: 100,
      unitOfMeasurement: 'units',
      storageLocation: 'Store A',
      qrCode: 'INV-LED',
      minimumThreshold: 10,
    });

    await db.doc('inventory_transactions/txn-1').set({
      inventoryItemId: 'inv-led',
      itemName: 'LED Bulbs',
      type: 'replenishment',
      quantity: 100,
      quantityBefore: 0,
      quantityAfter: 100,
      performedBy: ADMIN_UID,
    });

    await db.doc('audit_logs/audit-1').set({
      actorId: ADMIN_UID,
      actorName: 'Ramon Dela Cruz',
      action: 'created',
      entityType: 'damage_reports',
      entityId: 'rep-faculty',
      description: 'Report created',
    });

    await db.doc('feedback/fb-1').set({
      workOrderId: 'wo-assigned',
      reportId: 'rep-faculty',
      submittedBy: FACULTY_UID,
      responseTimeRating: 4,
      serviceQualityRating: 5,
      overallSatisfactionRating: 4,
    });

    await db.doc('config/prioritization').set({
      activeScheme: 'decimalWeights',
      minRating: 1,
      maxRating: 4,
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

const asAdmin = () => testEnv.authenticatedContext(ADMIN_UID).firestore();
const asFaculty = () => testEnv.authenticatedContext(FACULTY_UID).firestore();
const asPersonnel = () =>
  testEnv.authenticatedContext(PERSONNEL_UID).firestore();
const asInactive = () => testEnv.authenticatedContext(INACTIVE_UID).firestore();
const asAnonymous = () => testEnv.unauthenticatedContext().firestore();
const asPending = () => testEnv.authenticatedContext(PENDING_UID).firestore();
// Signed in with the account Firebase Auth just created, profile not yet
// written — the moment self-registration writes it.
const asNewSignUp = () =>
  testEnv
    .authenticatedContext(SIGNUP_UID, { email: SIGNUP_EMAIL })
    .firestore();

const serverNow = () => firebase.firestore.FieldValue.serverTimestamp();

/// The profile the faculty and staff sign-up writes (3.A), with
/// [overrides] applied.
const signUpProfile = (overrides = {}) => ({
  fullName: 'Liza Mae Tan',
  email: SIGNUP_EMAIL,
  role: 'requestor',
  accountStatus: 'pending',
  department: null,
  contactNumber: null,
  specialization: null,
  availability: null,
  activeTaskCount: 0,
  fcmToken: null,
  createdAt: serverNow(),
  updatedAt: serverNow(),
  ...overrides,
});

describe('unauthenticated access', () => {
  it('cannot read damage reports', async () => {
    await assertFails(asAnonymous().doc('damage_reports/rep-faculty').get());
  });

  it('cannot read facilities', async () => {
    await assertFails(asAnonymous().doc('facilities/fac-engineering').get());
  });

  it('cannot create a damage report', async () => {
    await assertFails(
      asAnonymous().collection('damage_reports').add({
        reporterId: 'anyone',
        description: 'Should be denied',
      }),
    );
  });
});

describe('self-registration (3.A)', () => {
  it('may file a request for their own account, pending approval', async () => {
    await assertSucceeds(
      asNewSignUp().doc(`users/${SIGNUP_UID}`).set(signUpProfile()),
    );
    // Cleaned up so the refusals below meet a missing document.
    await testEnv.withSecurityRulesDisabled((context) =>
      context.firestore().doc(`users/${SIGNUP_UID}`).delete(),
    );
  });

  it('cannot let themselves in, or as anything but a requestor', async () => {
    for (const overrides of [
      { accountStatus: 'active' },
      { role: 'admin' },
      { role: 'maintenancePersonnel' },
    ]) {
      await assertFails(
        asNewSignUp()
          .doc(`users/${SIGNUP_UID}`)
          .set(signUpProfile(overrides)),
      );
    }
  });

  it('cannot file under another address or another uid', async () => {
    await assertFails(
      asNewSignUp()
        .doc(`users/${SIGNUP_UID}`)
        .set(signUpProfile({ email: 'someone.else@dorsu.edu.ph' })),
    );
    await assertFails(
      asNewSignUp().doc('users/somebody-else').set(signUpProfile()),
    );
  });

  it('cannot carry personnel fields, extra fields or its own clock', async () => {
    for (const overrides of [
      { specialization: 'electrical' },
      { activeTaskCount: 3 },
      { isAdmin: true },
      { createdAt: new Date('2001-01-01T00:00:00Z') },
    ]) {
      await assertFails(
        asNewSignUp()
          .doc(`users/${SIGNUP_UID}`)
          .set(signUpProfile(overrides)),
      );
    }
  });

  it('is not open to anyone signed out', async () => {
    await assertFails(
      asAnonymous().doc(`users/${SIGNUP_UID}`).set(signUpProfile()),
    );
  });
});

describe('account awaiting approval (3.A)', () => {
  it('can read its own profile, so sign-in can say it is pending', async () => {
    await assertSucceeds(asPending().doc(`users/${PENDING_UID}`).get());
  });

  it('has no other access until approved', async () => {
    await assertFails(asPending().doc('facilities/fac-engineering').get());
    await assertFails(
      asPending()
        .collection('damage_reports')
        .where('reporterId', '==', PENDING_UID)
        .limit(10)
        .get(),
    );
  });

  it('cannot approve itself', async () => {
    await assertFails(
      asPending()
        .doc(`users/${PENDING_UID}`)
        .update({ accountStatus: 'active' }),
    );
  });

  it('is approved by an administrator', async () => {
    await assertSucceeds(
      asAdmin()
        .doc(`users/${PENDING_UID}`)
        .update({ accountStatus: 'active' }),
    );
    // Restored for any later test that relies on it being pending.
    await testEnv.withSecurityRulesDisabled((context) =>
      context
        .firestore()
        .doc(`users/${PENDING_UID}`)
        .update({ accountStatus: 'pending' }),
    );
  });
});

describe('deactivated account', () => {
  it('loses access despite valid credentials (§1.5)', async () => {
    await assertFails(asInactive().doc('facilities/fac-engineering').get());
    await assertFails(asInactive().doc('damage_reports/rep-faculty').get());
  });
});

describe('requestor (faculty/staff)', () => {
  it('can read their own report', async () => {
    await assertSucceeds(asFaculty().doc('damage_reports/rep-faculty').get());
  });

  it("cannot read another requestor's report", async () => {
    // The core isolation guarantee: one requestor must not be able to
    // browse everyone else's submissions.
    await assertFails(asFaculty().doc('damage_reports/rep-other').get());
  });

  it('can read facilities to fill in a report', async () => {
    await assertSucceeds(asFaculty().doc('facilities/fac-engineering').get());
  });

  it('can submit a report as themselves', async () => {
    await assertSucceeds(
      asFaculty().collection('damage_reports').add({
        reporterId: FACULTY_UID,
        reporterName: 'Maria Santos',
        title: 'New report',
        description: 'Something is broken.',
        requestorPriority: 'medium',
        status: 'submitted',
        officialPriority: null,
        duplicateOf: null,
        workOrderId: null,
      }),
    );
  });

  it('cannot submit a report impersonating someone else', async () => {
    await assertFails(
      asFaculty().collection('damage_reports').add({
        reporterId: OTHER_FACULTY_UID,
        reporterName: 'Other Faculty',
        title: 'Impersonated',
        description: 'Should be denied.',
        requestorPriority: 'medium',
        status: 'submitted',
        officialPriority: null,
        duplicateOf: null,
        workOrderId: null,
      }),
    );
  });

  it('cannot pre-set the official priority when submitting', async () => {
    // Official priority is the Administrator's decision alone (§1.2).
    await assertFails(
      asFaculty().collection('damage_reports').add({
        reporterId: FACULTY_UID,
        reporterName: 'Maria Santos',
        title: 'Self-prioritized',
        description: 'Should be denied.',
        requestorPriority: 'critical',
        status: 'submitted',
        officialPriority: 'critical',
        duplicateOf: null,
        workOrderId: null,
      }),
    );
  });

  // --- Objective 3.C: the mobile report form ---

  // What the form writes: every field of the report, the administrator's
  // ones null, plus photo evidence and a geo-tag.
  const fullSubmission = (overrides = {}) => ({
    reporterId: FACULTY_UID,
    reporterName: 'Maria Santos',
    title: 'Cracked window pane',
    description: 'The pane beside the door is cracked across.',
    category: null,
    classifiedAutomatically: false,
    requestorCategory: 'carpentry',
    facilityId: 'fac-engineering',
    facilityName: 'Engineering Building',
    locationDescription: 'Engineering Building, Room 101',
    assetId: null,
    coordinates: new GeoPoint(7.2048, 126.5354),
    photoUrls: ['https://example.test/photo-1.jpg'],
    requestorPriority: 'high',
    severityRating: null,
    safetyRiskRating: null,
    frequencyRating: null,
    locationImportanceRating: null,
    priorityScore: null,
    recommendedPriority: null,
    officialPriority: null,
    status: 'submitted',
    duplicateOf: null,
    workOrderId: null,
    reviewedBy: null,
    reviewedAt: null,
    rejectionReason: null,
    ...overrides,
  });

  it('can file a report with photos and a geo-tag the way the form does', async () => {
    // The form reads the id first inside a transaction, so a retry after a
    // timeout cannot file twice, and writes the audit entry alongside.
    const db = asFaculty();
    const report = db.collection('damage_reports').doc();
    await assertSucceeds(
      db.runTransaction(async (transaction) => {
        const existing = await transaction.get(report);
        assert.equal(existing.exists, false);
        transaction.set(report, fullSubmission());
        transaction.set(db.collection('audit_logs').doc(), {
          actorId: FACULTY_UID,
          actorName: 'Maria Santos',
          action: 'created',
          entityType: 'damage_reports',
          entityId: report.id,
          description: 'Submitted "Cracked window pane"',
        });
      }),
    );
  });

  it('cannot file over a report that already exists', async () => {
    // A second write to the same id is an update, which requestors never
    // get — so a duplicate submission can only ever be a no-op.
    await assertFails(
      asFaculty().doc('damage_reports/rep-faculty').set(fullSubmission()),
    );
  });

  it('cannot pre-set a review decision when submitting', async () => {
    await assertFails(
      asFaculty()
        .collection('damage_reports')
        .add(fullSubmission({ reviewedBy: ADMIN_UID })),
    );
    await assertFails(
      asFaculty()
        .collection('damage_reports')
        .add(fullSubmission({ rejectionReason: 'Pre-rejected' })),
    );
  });

  it('cannot submit a malformed report', async () => {
    for (const overrides of [
      { description: '' },
      { title: '' },
      { requestorPriority: 'extreme' },
      { requestorCategory: 'nuclear' },
      { coordinates: 'Engineering Building' },
      { photoUrls: Array.from({ length: 11 }, (_, i) => `photo-${i}.jpg`) },
    ]) {
      await assertFails(
        asFaculty().collection('damage_reports').add(fullSubmission(overrides)),
      );
    }
  });

  it("cannot list other requestors' reports", async () => {
    // Listing was gated on page size alone until 3.C, which let any
    // requestor query every report in the system.
    await assertFails(
      asFaculty().collection('damage_reports').limit(50).get(),
    );
  });

  it('can list their own reports', async () => {
    await assertSucceeds(
      asFaculty()
        .collection('damage_reports')
        .where('reporterId', '==', FACULTY_UID)
        .limit(50)
        .get(),
    );
  });

  it('lists their own reports only in pages of at most 100', async () => {
    // The app's own-report query (3.A) asks for exactly the maximum.
    await assertSucceeds(
      asFaculty()
        .collection('damage_reports')
        .where('reporterId', '==', FACULTY_UID)
        .orderBy('submittedAt', 'desc')
        .limit(100)
        .get(),
    );
    await assertFails(
      asFaculty()
        .collection('damage_reports')
        .where('reporterId', '==', FACULTY_UID)
        .limit(101)
        .get(),
    );
    // No limit at all — how watchByReporter asked until 3.A.
    await assertFails(
      asFaculty()
        .collection('damage_reports')
        .where('reporterId', '==', FACULTY_UID)
        .get(),
    );
  });

  it('cannot escalate their own role to admin', async () => {
    await assertFails(
      asFaculty().doc(`users/${FACULTY_UID}`).update({ role: 'admin' }),
    );
  });

  it('cannot reactivate or change their own account status', async () => {
    await assertFails(
      asFaculty()
        .doc(`users/${FACULTY_UID}`)
        .update({ accountStatus: 'inactive' }),
    );
  });

  it('can update their own contact details', async () => {
    await assertSucceeds(
      asFaculty()
        .doc(`users/${FACULTY_UID}`)
        .update({ contactNumber: '09170000000' }),
    );
  });

  it("cannot read another user's profile", async () => {
    await assertFails(asFaculty().doc(`users/${PERSONNEL_UID}`).get());
  });

  it('cannot create a work order', async () => {
    await assertFails(
      asFaculty().collection('work_orders').add({
        reportIds: ['rep-faculty'],
        title: 'Unauthorized',
        description: 'Should be denied',
        category: 'electrical',
        priority: 'low',
        status: 'pending',
        createdBy: FACULTY_UID,
      }),
    );
  });

  it('cannot modify inventory', async () => {
    await assertFails(
      asFaculty().doc('inventory_items/inv-led').update({
        quantityAvailable: 0,
      }),
    );
  });

  it('can read their own feedback but not everyone else’s', async () => {
    await assertSucceeds(asFaculty().doc('feedback/fb-1').get());
  });
});

describe('maintenance personnel', () => {
  it('can read an assigned work order', async () => {
    await assertSucceeds(asPersonnel().doc('work_orders/wo-assigned').get());
  });

  it('cannot read a work order assigned to someone else', async () => {
    await assertFails(asPersonnel().doc('work_orders/wo-unassigned').get());
  });

  it('can update status on an assigned work order', async () => {
    await assertSucceeds(
      asPersonnel().doc('work_orders/wo-assigned').update({
        status: 'inProgress',
      }),
    );
  });

  it('cannot reassign a work order to themselves', async () => {
    await assertFails(
      asPersonnel()
        .doc('work_orders/wo-assigned')
        .update({ assignedPersonnelIds: [PERSONNEL_UID, ADMIN_UID] }),
    );
  });

  it('cannot update an unassigned work order', async () => {
    await assertFails(
      asPersonnel().doc('work_orders/wo-unassigned').update({
        status: 'inProgress',
      }),
    );
  });

  it('can read inventory items', async () => {
    await assertSucceeds(asPersonnel().doc('inventory_items/inv-led').get());
  });

  it('cannot delete an inventory item', async () => {
    await assertFails(asPersonnel().doc('inventory_items/inv-led').delete());
  });

  it('cannot read feedback (§1.5: not a performance evaluation)', async () => {
    // §1.5: submitted ratings "do not automatically determine personnel
    // performance evaluations". Personnel therefore cannot see them.
    await assertFails(asPersonnel().doc('feedback/fb-1').get());
  });

  it('cannot create a work order', async () => {
    await assertFails(
      asPersonnel().collection('work_orders').add({
        reportIds: ['rep-faculty'],
        title: 'Self-assigned',
        description: 'Should be denied',
        category: 'electrical',
        priority: 'low',
        status: 'pending',
        createdBy: PERSONNEL_UID,
      }),
    );
  });

  it('cannot create a user account', async () => {
    await assertFails(
      asPersonnel().doc('users/new-user').set({
        fullName: 'Invented',
        email: 'invented@dorsu.edu.ph',
        role: 'admin',
        accountStatus: 'active',
      }),
    );
  });
});

describe('append-only collections', () => {
  it('nobody, including an admin, can edit an inventory transaction', async () => {
    // The ledger's immutability is the whole reason it is trustworthy.
    await assertFails(
      asAdmin().doc('inventory_transactions/txn-1').update({ quantity: 999 }),
    );
    await assertFails(asAdmin().doc('inventory_transactions/txn-1').delete());
    await assertFails(
      asPersonnel()
        .doc('inventory_transactions/txn-1')
        .update({ quantity: 999 }),
    );
  });

  it('an admin can append a new inventory transaction', async () => {
    await assertSucceeds(
      asAdmin().collection('inventory_transactions').add({
        inventoryItemId: 'inv-led',
        itemName: 'LED Bulbs',
        type: 'replenishment',
        quantity: 10,
        quantityBefore: 100,
        quantityAfter: 110,
        performedBy: ADMIN_UID,
      }),
    );
  });

  it('nobody, including an admin, can edit an audit log entry', async () => {
    await assertFails(
      asAdmin().doc('audit_logs/audit-1').update({ description: 'Rewritten' }),
    );
    await assertFails(asAdmin().doc('audit_logs/audit-1').delete());
  });
});

describe('administrator', () => {
  it('can read any damage report', async () => {
    await assertSucceeds(asAdmin().doc('damage_reports/rep-other').get());
  });

  it('can read any user profile', async () => {
    await assertSucceeds(asAdmin().doc(`users/${PERSONNEL_UID}`).get());
  });

  it('can set the official priority on a report', async () => {
    await assertSucceeds(
      asAdmin()
        .doc('damage_reports/rep-faculty')
        .update({ officialPriority: 'critical' }),
    );
  });

  it('can create a work order', async () => {
    await assertSucceeds(
      asAdmin().collection('work_orders').add({
        reportIds: ['rep-faculty'],
        title: 'Legitimate',
        description: 'Raised by an administrator',
        category: 'electrical',
        priority: 'high',
        status: 'pending',
        createdBy: ADMIN_UID,
      }),
    );
  });

  it('can deactivate a user account', async () => {
    await assertSucceeds(
      asAdmin()
        .doc(`users/${OTHER_FACULTY_UID}`)
        .update({ accountStatus: 'inactive' }),
    );
  });

  it("can change another account's role", async () => {
    await assertSucceeds(
      asAdmin()
        .doc(`users/${OTHER_FACULTY_UID}`)
        .update({ role: 'maintenancePersonnel' }),
    );
  });

  // 2.C: an administrator locking themselves out could leave nobody able
  // to manage accounts. The repository refuses too, but a client that
  // skipped it must be stopped here.
  it('cannot deactivate their own account', async () => {
    await assertFails(
      asAdmin().doc(`users/${ADMIN_UID}`).update({ accountStatus: 'inactive' }),
    );
  });

  it('cannot change their own role', async () => {
    await assertFails(
      asAdmin().doc(`users/${ADMIN_UID}`).update({ role: 'requestor' }),
    );
  });

  it('can still edit their own contact details', async () => {
    await assertSucceeds(
      asAdmin()
        .doc(`users/${ADMIN_UID}`)
        .update({ contactNumber: '09170000000' }),
    );
  });

  it('can update configuration', async () => {
    await assertSucceeds(
      asAdmin().doc('config/prioritization').update({ maxRating: 5 }),
    );
  });

  it('cannot delete a damage report', async () => {
    // Reports are archived, never destroyed — the audit trail depends on
    // them continuing to exist.
    await assertFails(asAdmin().doc('damage_reports/rep-faculty').delete());
  });

  it('cannot delete a user account', async () => {
    await assertFails(asAdmin().doc(`users/${FACULTY_UID}`).delete());
  });
});

describe('status history (3.B)', () => {
  // Each test seeds its own report, so none depends on another's moves.
  const seedReport = (id, data = {}) =>
    testEnv.withSecurityRulesDisabled((context) =>
      context.firestore().doc(`damage_reports/${id}`).set({
        reporterId: FACULTY_UID,
        reporterName: 'Maria Santos',
        title: 'Flickering lights',
        description: 'Lights in Room 101 flicker constantly.',
        requestorPriority: 'high',
        status: 'underReview',
        workOrderId: null,
        ...data,
      }),
    );

  const seedEntry = (reportId) =>
    testEnv.withSecurityRulesDisabled((context) =>
      context.firestore().doc(`damage_reports/${reportId}/status_history/e1`).set({
        status: 'submitted',
        changedAt: firebase.firestore.Timestamp.now(),
        changedBy: FACULTY_UID,
      }),
    );

  const historyOf = (db, reportId) =>
    db.collection(`damage_reports/${reportId}/status_history`);

  /// What the repositories write, with [overrides] applied.
  const entry = (overrides = {}) => ({
    status: 'approved',
    changedAt: serverNow(),
    changedBy: ADMIN_UID,
    note: null,
    personnelName: null,
    personnelSpecialization: null,
    ...overrides,
  });

  /// Moves [reportId] to [status] and records it, in one batch, as [db].
  const move = (db, reportId, status, entryOverrides = {}) => {
    const batch = db.batch();
    batch.update(db.doc(`damage_reports/${reportId}`), { status });
    batch.set(historyOf(db, reportId).doc(), entry({ status, ...entryOverrides }));
    return batch.commit();
  };

  it('a requestor reads the history of their own report', async () => {
    await seedReport('h-own');
    await seedEntry('h-own');
    await assertSucceeds(historyOf(asFaculty(), 'h-own').orderBy('changedAt').get());
  });

  it("a requestor cannot read another requestor's history", async () => {
    await seedReport('h-other', { reporterId: OTHER_FACULTY_UID });
    await seedEntry('h-other');
    await assertFails(historyOf(asFaculty(), 'h-other').get());
    await assertFails(asFaculty().doc('damage_reports/h-other/status_history/e1').get());
  });

  it('a deactivated account cannot read even its own history', async () => {
    await seedReport('h-inactive', { reporterId: INACTIVE_UID });
    await assertFails(historyOf(asInactive(), 'h-inactive').get());
  });

  it('a requestor starts the history while filing their report', async () => {
    const db = asFaculty();
    const report = db.collection('damage_reports').doc();
    const batch = db.batch();
    batch.set(report, {
      reporterId: FACULTY_UID,
      reporterName: 'Maria Santos',
      title: 'Cracked window pane',
      description: 'The pane beside the door is cracked across.',
      requestorPriority: 'high',
      status: 'submitted',
    });
    batch.set(
      historyOf(db, report.id).doc(),
      entry({ status: 'submitted', changedBy: FACULTY_UID }),
    );
    await assertSucceeds(batch.commit());
  });

  it('a requestor cannot add to the history of an existing report', async () => {
    // Their own report, already filed: anything they add now would be a
    // claim about progress they do not make.
    await seedReport('h-filed', { status: 'submitted' });
    await assertFails(
      historyOf(asFaculty(), 'h-filed').add(
        entry({ status: 'submitted', changedBy: FACULTY_UID }),
      ),
    );
  });

  it('a requestor cannot open the history at a later stage', async () => {
    const db = asFaculty();
    const report = db.collection('damage_reports').doc();
    const batch = db.batch();
    batch.set(report, {
      reporterId: FACULTY_UID,
      reporterName: 'Maria Santos',
      title: 'Cracked window pane',
      description: 'The pane beside the door is cracked across.',
      requestorPriority: 'high',
      status: 'submitted',
    });
    batch.set(
      historyOf(db, report.id).doc(),
      entry({ status: 'completed', changedBy: FACULTY_UID }),
    );
    await assertFails(batch.commit());
  });

  it("an administrator's move records its entry alongside", async () => {
    await seedReport('h-approve');
    await assertSucceeds(move(asAdmin(), 'h-approve', 'approved'));
  });

  it('an entry must name the status the report actually has', async () => {
    // The report stays under review; an entry saying "completed" would
    // put a move on the timeline that never happened.
    await seedReport('h-claim');
    await assertFails(
      historyOf(asAdmin(), 'h-claim').add(entry({ status: 'completed' })),
    );
  });

  it('an entry is stamped by its writer, at server time', async () => {
    await seedReport('h-stamp-1');
    await assertFails(
      move(asAdmin(), 'h-stamp-1', 'approved', { changedBy: FACULTY_UID }),
    );
    await seedReport('h-stamp-2');
    await assertFails(
      move(asAdmin(), 'h-stamp-2', 'approved', {
        changedAt: firebase.firestore.Timestamp.fromDate(new Date(2020, 0, 1)),
      }),
    );
  });

  it('an entry carries only the fields the timeline reads', async () => {
    await seedReport('h-extra');
    await assertFails(
      move(asAdmin(), 'h-extra', 'approved', { officialPriority: 'critical' }),
    );
  });

  it('personnel record a move on a report with a work order', async () => {
    await seedReport('h-worked', {
      status: 'assigned',
      workOrderId: 'wo-assigned',
    });
    await assertSucceeds(
      move(asPersonnel(), 'h-worked', 'inProgress', { changedBy: PERSONNEL_UID }),
    );
  });

  it('personnel cannot record a move on a report with no work order', async () => {
    await seedReport('h-unworked', { status: 'approved' });
    await assertFails(
      historyOf(asPersonnel(), 'h-unworked').add(
        entry({ status: 'approved', changedBy: PERSONNEL_UID }),
      ),
    );
  });

  it('nobody, an administrator included, can edit or delete an entry', async () => {
    await seedReport('h-locked');
    await seedEntry('h-locked');
    const path = 'damage_reports/h-locked/status_history/e1';
    await assertFails(asAdmin().doc(path).update({ status: 'approved' }));
    await assertFails(asAdmin().doc(path).delete());
    await assertFails(asFaculty().doc(path).delete());
  });
});

describe('notifications (3.B)', () => {
  const seed = (path, data) =>
    testEnv.withSecurityRulesDisabled((context) =>
      context.firestore().doc(path).set(data),
    );

  const seedReport = (id, data = {}) =>
    seed(`damage_reports/${id}`, {
      reporterId: FACULTY_UID,
      reporterName: 'Maria Santos',
      title: 'Flickering lights',
      description: 'Lights in Room 101 flicker constantly.',
      requestorPriority: 'high',
      status: 'underReview',
      workOrderId: null,
      ...data,
    });

  const seedNotice = (id, data = {}) =>
    seed(`notifications/${id}`, {
      recipientId: FACULTY_UID,
      type: 'statusUpdate',
      title: 'Report approved',
      body: 'Your report was approved.',
      relatedEntityType: 'damage_reports',
      relatedEntityId: 'rep-faculty',
      isRead: false,
      readAt: null,
      createdAt: firebase.firestore.Timestamp.now(),
      ...data,
    });

  /// A notice as the repositories write it, with [overrides] applied.
  const notice = (reportId, overrides = {}) => ({
    recipientId: FACULTY_UID,
    type: 'statusUpdate',
    title: 'Report approved',
    body: 'Your report "Flickering lights" was approved.',
    relatedEntityType: 'damage_reports',
    relatedEntityId: reportId,
    isRead: false,
    readAt: null,
    createdAt: serverNow(),
    ...overrides,
  });

  const filing = (db, report, noticeOverrides = {}) => {
    const batch = db.batch();
    batch.set(report, {
      reporterId: FACULTY_UID,
      reporterName: 'Maria Santos',
      title: 'Cracked window pane',
      description: 'The pane beside the door is cracked across.',
      requestorPriority: 'high',
      status: 'submitted',
    });
    batch.set(
      db.collection('notifications').doc(),
      notice(report.id, { type: 'reportAcknowledged', title: 'Report received', ...noticeOverrides }),
    );
    return batch;
  };

  it('a requestor reads their own notifications', async () => {
    await seedNotice('n-own');
    await assertSucceeds(asFaculty().doc('notifications/n-own').get());
    await assertSucceeds(
      asFaculty()
        .collection('notifications')
        .where('recipientId', '==', FACULTY_UID)
        .orderBy('createdAt', 'desc')
        .limit(100)
        .get(),
    );
  });

  it("a requestor cannot read anyone else's", async () => {
    await seedNotice('n-other', { recipientId: OTHER_FACULTY_UID });
    await assertFails(asFaculty().doc('notifications/n-other').get());
    await assertFails(
      asFaculty()
        .collection('notifications')
        .where('recipientId', '==', OTHER_FACULTY_UID)
        .get(),
    );
    // Nor the whole collection.
    await assertFails(asFaculty().collection('notifications').limit(10).get());
  });

  it('a deactivated account cannot read even its own', async () => {
    await seedNotice('n-inactive', { recipientId: INACTIVE_UID });
    await assertFails(asInactive().doc('notifications/n-inactive').get());
  });

  it('a requestor marks their own notification read, and only that', async () => {
    await seedNotice('n-read');
    const doc = asFaculty().doc('notifications/n-read');
    await assertFails(doc.update({ title: 'Something else' }));
    await assertFails(
      doc.update({ isRead: true, readAt: serverNow(), recipientId: OTHER_FACULTY_UID }),
    );
    await assertSucceeds(doc.update({ isRead: true, readAt: serverNow() }));
  });

  it('a read notification is not marked unread again', async () => {
    await seedNotice('n-done', {
      isRead: true,
      readAt: firebase.firestore.Timestamp.now(),
    });
    await assertFails(
      asFaculty()
        .doc('notifications/n-done')
        .update({ isRead: false, readAt: serverNow() }),
    );
  });

  it("a requestor cannot mark someone else's notification read", async () => {
    await seedNotice('n-theirs', { recipientId: OTHER_FACULTY_UID });
    await assertFails(
      asFaculty()
        .doc('notifications/n-theirs')
        .update({ isRead: true, readAt: serverNow() }),
    );
  });

  it('a requestor gets their own "received" notice while filing', async () => {
    const db = asFaculty();
    await assertSucceeds(filing(db, db.collection('damage_reports').doc()).commit());
  });

  it('a requestor cannot create a notification for anyone else', async () => {
    const db = asFaculty();
    // Addressed to another person while filing their own report.
    await assertFails(
      filing(db, db.collection('damage_reports').doc(), {
        recipientId: OTHER_FACULTY_UID,
      }).commit(),
    );
    // About another person's report.
    await seedReport('nr-other', { reporterId: OTHER_FACULTY_UID });
    await assertFails(
      db.collection('notifications').add(
        notice('nr-other', {
          recipientId: OTHER_FACULTY_UID,
          type: 'reportAcknowledged',
        }),
      ),
    );
  });

  it('a requestor cannot notify themselves of progress', async () => {
    // Only the acknowledgment, only while filing: anything else would be a
    // claim about GSU's progress that GSU never made.
    await seedReport('nr-mine');
    await assertFails(asFaculty().collection('notifications').add(notice('nr-mine')));
    await assertFails(
      asFaculty()
        .collection('notifications')
        .add(notice('nr-mine', { type: 'reportAcknowledged' })),
    );
    const db = asFaculty();
    await assertFails(
      filing(db, db.collection('damage_reports').doc(), {
        type: 'maintenanceCompleted',
      }).commit(),
    );
  });

  it("an administrator notifies a report's reporter with the move", async () => {
    await seedReport('nr-approve');
    const db = asAdmin();
    const batch = db.batch();
    batch.update(db.doc('damage_reports/nr-approve'), { status: 'approved' });
    batch.set(db.collection('notifications').doc(), notice('nr-approve'));
    await assertSucceeds(batch.commit());
  });

  it("an administrator cannot address a report's notice to someone else", async () => {
    await seedReport('nr-misaddressed');
    await assertFails(
      asAdmin()
        .collection('notifications')
        .add(notice('nr-misaddressed', { recipientId: OTHER_FACULTY_UID })),
    );
  });

  it('a new notification is unread and stamped at server time', async () => {
    await seedReport('nr-shape');
    const db = asAdmin();
    await assertFails(
      db.collection('notifications').add(
        notice('nr-shape', { isRead: true, readAt: serverNow() }),
      ),
    );
    await assertFails(
      db.collection('notifications').add(
        notice('nr-shape', {
          createdAt: firebase.firestore.Timestamp.fromDate(new Date(2020, 0, 1)),
        }),
      ),
    );
    await assertFails(
      db.collection('notifications').add(notice('nr-shape', { type: 'nonsense' })),
    );
  });

  it('personnel notify the reporter of a report they are working', async () => {
    await seedReport('nr-worked', { status: 'assigned', workOrderId: 'wo-assigned' });
    const db = asPersonnel();
    const batch = db.batch();
    batch.update(db.doc('damage_reports/nr-worked'), { status: 'inProgress' });
    batch.set(
      db.collection('notifications').doc(),
      notice('nr-worked', { title: 'Work started' }),
    );
    await assertSucceeds(batch.commit());
  });

  it('personnel cannot notify about a report with no work order', async () => {
    await seedReport('nr-unworked', { status: 'approved' });
    await assertFails(
      asPersonnel().collection('notifications').add(notice('nr-unworked')),
    );
  });
});

describe('unknown collections', () => {
  it('are denied by the catch-all rule', async () => {
    await assertFails(asAdmin().doc('not_a_real_collection/doc').get());
    await assertFails(
      asAdmin().doc('not_a_real_collection/doc').set({ a: 1 }),
    );
  });
});

assert.ok(true, 'module loaded');
