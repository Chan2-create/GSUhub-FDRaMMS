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
import {
  GeoPoint,
  collection,
  getCountFromServer,
  query,
  where,
} from 'firebase/firestore';

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

  // --- Objectives 4.A–4.C: classified on the phone, reviewed by GSU ---

  const file = (overrides) =>
    asFaculty().collection('damage_reports').add(fullSubmission(overrides));

  it("may file the keyword classifier's damage type, marked automatic", async () => {
    // No Cloud Functions on the Spark plan: the phone runs the classifier.
    await assertSucceeds(
      file({
        category: 'electrical',
        classifiedAutomatically: true,
        dismissedDuplicateIds: [],
      }),
    );
  });

  it('cannot file a damage type as if an administrator had set it', async () => {
    for (const overrides of [
      { category: 'electrical', classifiedAutomatically: false },
      { category: 'electrical', classifiedAutomatically: null },
      { category: null, classifiedAutomatically: true },
      { category: 'nuclear', classifiedAutomatically: true },
    ]) {
      await assertFails(file(overrides));
    }
  });

  it('cannot pre-set the ratings, the score or the recommendation', async () => {
    for (const overrides of [
      { severityRating: 4 },
      { safetyRiskRating: 4 },
      { frequencyRating: 4 },
      { locationImportanceRating: 4 },
      { priorityScore: 4.0 },
      { recommendedPriority: 'critical' },
    ]) {
      await assertFails(file(overrides));
    }
  });

  it('cannot pre-set which reports it is not a duplicate of', async () => {
    await assertFails(file({ dismissedDuplicateIds: ['rep-other'] }));
  });

  it('can read the keyword list it classifies with, but not change it', async () => {
    await assertSucceeds(asFaculty().doc('config/classification_rules').get());
    await assertFails(
      asFaculty().doc('config/classification_rules').set({
        keywordsByCategory: { electrical: ['anything'] },
        caseSensitive: false,
        updatedAt: serverNow(),
        updatedBy: FACULTY_UID,
      }),
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

  it('can save the keyword list from Settings (4.A)', async () => {
    await assertSucceeds(
      asAdmin().doc('config/classification_rules').set({
        keywordsByCategory: {
          electrical: ['power outage', 'exposed wire'],
          generalMaintenance: [],
        },
        caseSensitive: false,
        updatedAt: serverNow(),
        updatedBy: ADMIN_UID,
      }),
    );
  });

  it('can record a review: type, ratings, score and official priority (4.C)', async () => {
    await assertSucceeds(
      asAdmin().doc('damage_reports/rep-faculty').update({
        category: 'plumbing',
        classifiedAutomatically: false,
        severityRating: 4,
        safetyRiskRating: 4,
        frequencyRating: 2,
        locationImportanceRating: 3,
        priorityScore: 3.5,
        recommendedPriority: 'critical',
        officialPriority: 'critical',
        reviewedBy: ADMIN_UID,
        reviewedAt: serverNow(),
        updatedAt: serverNow(),
      }),
    );
  });

  it('can keep two reports separate, on both (4.C)', async () => {
    const db = asAdmin();
    await assertSucceeds(
      db.runTransaction(async (transaction) => {
        transaction.update(db.doc('damage_reports/rep-faculty'), {
          dismissedDuplicateIds: firebase.firestore.FieldValue.arrayUnion(
            'rep-other',
          ),
        });
        transaction.update(db.doc('damage_reports/rep-other'), {
          dismissedDuplicateIds: firebase.firestore.FieldValue.arrayUnion(
            'rep-faculty',
          ),
        });
      }),
    );
  });

  it('can count similar reports for the Frequency hint (4.B)', async () => {
    // A count is authorized by the list rule. The compat SDK the other
    // tests use has no count(), so this one goes through the modular API.
    const db = asAdmin()._delegate;
    await assertSucceeds(
      getCountFromServer(
        query(
          collection(db, 'damage_reports'),
          where('facilityId', '==', 'fac-engineering'),
          where('category', '==', 'electrical'),
        ),
      ),
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

describe('rating the service (3.C)', () => {
  // Each test seeds its own completed report, so none depends on another.
  const seedCompleted = (id, data = {}) =>
    testEnv.withSecurityRulesDisabled((context) =>
      context.firestore().doc(`damage_reports/${id}`).set({
        reporterId: FACULTY_UID,
        reporterName: 'Maria Santos',
        title: 'Flickering lights',
        description: 'Lights in Room 101 flicker constantly.',
        requestorPriority: 'high',
        status: 'completed',
        workOrderId: 'wo-assigned',
        ...data,
      }),
    );

  /// The rating the app files, with [overrides] applied.
  const rating = (reportId, overrides = {}) => ({
    workOrderId: 'wo-assigned',
    reportId,
    submittedBy: FACULTY_UID,
    responseTimeRating: 4,
    serviceQualityRating: 5,
    overallSatisfactionRating: 3,
    comments: 'Quick and tidy.',
    submittedAt: serverNow(),
    ...overrides,
  });

  /// What the rating transaction writes: the rating, the report's close,
  /// its timeline entry and the audit entry. [skip] leaves parts out.
  const rateAndClose = (db, reportId, { overrides = {}, skip = [] } = {}) => {
    const batch = db.batch();
    if (!skip.includes('rating')) {
      batch.set(db.doc(`feedback/${reportId}`), rating(reportId, overrides));
    }
    if (!skip.includes('close')) {
      batch.update(db.doc(`damage_reports/${reportId}`), {
        status: 'closed',
        updatedAt: serverNow(),
      });
    }
    if (!skip.includes('history')) {
      batch.set(db.collection(`damage_reports/${reportId}/status_history`).doc(), {
        status: 'closed',
        changedAt: serverNow(),
        changedBy: FACULTY_UID,
        note: null,
        personnelName: null,
        personnelSpecialization: null,
      });
    }
    batch.set(db.collection('audit_logs').doc(), {
      actorId: FACULTY_UID,
      actorName: 'Maria Santos',
      action: 'statusChanged',
      entityType: 'damage_reports',
      entityId: reportId,
      description: 'Rated the service and closed the report',
    });
    return batch.commit();
  };

  it('a requestor rates their completed report, closing it', async () => {
    await seedCompleted('rt-ok');
    await assertSucceeds(rateAndClose(asFaculty(), 'rt-ok'));
  });

  it('a rating without comments is fine', async () => {
    await seedCompleted('rt-nocomment');
    await assertSucceeds(
      rateAndClose(asFaculty(), 'rt-nocomment', { overrides: { comments: null } }),
    );
  });

  it('cannot rate without closing the report', async () => {
    await seedCompleted('rt-noclose');
    await assertFails(rateAndClose(asFaculty(), 'rt-noclose', { skip: ['close'] }));
  });

  it('cannot close the report without rating it', async () => {
    await seedCompleted('rt-norating');
    await assertFails(rateAndClose(asFaculty(), 'rt-norating', { skip: ['rating'] }));
  });

  it("cannot rate another requestor's report", async () => {
    await seedCompleted('rt-other', { reporterId: OTHER_FACULTY_UID });
    await assertFails(rateAndClose(asFaculty(), 'rt-other'));
  });

  it('cannot rate work that is not completed', async () => {
    await seedCompleted('rt-early', { status: 'inProgress' });
    await assertFails(rateAndClose(asFaculty(), 'rt-early'));
  });

  it('cannot rate under another work order, as someone else, or off the scale', async () => {
    await seedCompleted('rt-bad');
    for (const overrides of [
      { workOrderId: 'wo-unassigned' },
      { submittedBy: OTHER_FACULTY_UID },
      { responseTimeRating: 6 },
      { serviceQualityRating: 0 },
      { overallSatisfactionRating: 4.5 },
      { comments: 'x'.repeat(1001) },
      { score: 5 },
      { submittedAt: firebase.firestore.Timestamp.fromDate(new Date(2020, 0, 1)) },
    ]) {
      await assertFails(rateAndClose(asFaculty(), 'rt-bad', { overrides }));
    }
  });

  it('cannot file a rating under another id than its report', async () => {
    await seedCompleted('rt-id');
    const db = asFaculty();
    const batch = db.batch();
    batch.set(db.doc('feedback/some-other-id'), rating('rt-id'));
    batch.update(db.doc('damage_reports/rt-id'), {
      status: 'closed',
      updatedAt: serverNow(),
    });
    await assertFails(batch.commit());
  });

  it('cannot rate twice, or change a rating', async () => {
    await seedCompleted('rt-twice');
    await assertSucceeds(rateAndClose(asFaculty(), 'rt-twice'));
    await assertFails(
      asFaculty().doc('feedback/rt-twice').set(rating('rt-twice', { overallSatisfactionRating: 1 })),
    );
    await assertFails(
      asFaculty().doc('feedback/rt-twice').update({ overallSatisfactionRating: 1 }),
    );
  });

  it('can ask whether their report was rated before rating it', async () => {
    // The rating transaction reads first, so a second tap cannot rate twice.
    await assertSucceeds(asFaculty().doc('feedback/never-rated').get());
  });

  it('personnel and other requestors cannot read a rating', async () => {
    await seedCompleted('rt-read');
    await assertSucceeds(rateAndClose(asFaculty(), 'rt-read'));
    await assertSucceeds(asFaculty().doc('feedback/rt-read').get());
    await assertFails(asPersonnel().doc('feedback/rt-read').get());
    await assertFails(
      testEnv.authenticatedContext(OTHER_FACULTY_UID).firestore().doc('feedback/rt-read').get(),
    );
  });

  it('an administrator lists every rating', async () => {
    await assertSucceeds(asAdmin().collection('feedback').get());
  });

  it('a requestor cannot otherwise move their own report', async () => {
    await seedCompleted('rt-move', { status: 'approved' });
    await assertFails(
      asFaculty().doc('damage_reports/rt-move').update({
        status: 'closed',
        updatedAt: serverNow(),
      }),
    );
  });
});

describe('personnel work (5.A–5.C)', () => {
  // Each test seeds the work orders it touches, so none depends on
  // another's moves.
  const seed = (path, data) =>
    testEnv.withSecurityRulesDisabled((context) =>
      context.firestore().doc(path).set(data),
    );

  const seedWorkOrder = (id, data = {}) =>
    seed(`work_orders/${id}`, {
      reportIds: ['rep-faculty'],
      title: 'Repair ceiling fan',
      description: 'Replace bearing.',
      category: 'electrical',
      priority: 'high',
      status: 'inProgress',
      assignedPersonnelIds: [PERSONNEL_UID],
      adminNotes: null,
      createdBy: ADMIN_UID,
      ...data,
    });

  const seedTask = (id, data = {}) =>
    seed(`tasks/${id}`, {
      workOrderId: 'wo-assigned',
      title: 'Replace the bearing',
      description: null,
      assignedTo: PERSONNEL_UID,
      status: 'pending',
      proofPhotoUrls: [],
      completedAt: null,
      ...data,
    });

  /// A recorded material as the repository writes it.
  const material = (overrides = {}) => ({
    itemName: 'LED Bulbs',
    quantityUsed: 2,
    unitOfMeasurement: 'units',
    recordedBy: PERSONNEL_UID,
    recordedAt: serverNow(),
    ...overrides,
  });

  /// An accomplishment report as the repository files it.
  const accomplishment = (workOrderId, overrides = {}) => ({
    workOrderId,
    submittedBy: PERSONNEL_UID,
    completionNotes: 'Replaced the bearing and tested the fan.',
    photoUrls: ['https://example.test/after.jpg'],
    materialsUsed: [],
    inventoryDeducted: false,
    reviewedBy: null,
    reviewedAt: null,
    submittedAt: serverNow(),
    ...overrides,
  });

  /// Files [report] in the same batch that moves [workOrderId] to for
  /// review, as [db].
  const submit = (db, reportId, workOrderId, report, { moveTo = 'forReview' } = {}) => {
    const batch = db.batch();
    batch.update(db.doc(`work_orders/${workOrderId}`), {
      status: moveTo,
      updatedAt: serverNow(),
    });
    batch.set(db.doc(`accomplishment_reports/${reportId}`), report);
    return batch.commit();
  };

  describe('work orders', () => {
    it('personnel list their own work orders, not everyone’s', async () => {
      await assertSucceeds(
        asPersonnel()
          .collection('work_orders')
          .where('assignedPersonnelIds', 'array-contains', PERSONNEL_UID)
          .get(),
      );
      await assertFails(asPersonnel().collection('work_orders').get());
    });

    it('personnel start pending work and submit work in progress', async () => {
      await seedWorkOrder('pw-start', { status: 'pending' });
      await assertSucceeds(
        asPersonnel().doc('work_orders/pw-start').update({
          status: 'inProgress',
          startedAt: serverNow(),
          updatedAt: serverNow(),
        }),
      );
      await assertSucceeds(
        asPersonnel().doc('work_orders/pw-start').update({
          status: 'forReview',
          updatedAt: serverNow(),
        }),
      );
    });

    it('sign-off, send-back and skipping ahead are the administrator’s', async () => {
      await seedWorkOrder('pw-review', { status: 'forReview' });
      await assertFails(
        asPersonnel().doc('work_orders/pw-review').update({ status: 'completed' }),
      );
      await assertFails(
        asPersonnel().doc('work_orders/pw-review').update({ status: 'inProgress' }),
      );
      await seedWorkOrder('pw-skip', { status: 'pending' });
      await assertFails(
        asPersonnel().doc('work_orders/pw-skip').update({ status: 'completed' }),
      );
      await assertFails(
        asPersonnel().doc('work_orders/pw-skip').update({ status: 'forReview' }),
      );
      await assertSucceeds(
        asAdmin().doc('work_orders/pw-review').update({ status: 'completed' }),
      );
    });

    it('personnel cannot rewrite the work order while moving it', async () => {
      await seedWorkOrder('pw-rewrite', { status: 'pending' });
      await assertFails(
        asPersonnel().doc('work_orders/pw-rewrite').update({
          status: 'inProgress',
          adminNotes: 'Done, trust me.',
        }),
      );
    });

    it('personnel read a report only when it is their work', async () => {
      await seed('damage_reports/pw-mine', {
        reporterId: FACULTY_UID,
        title: 'Flickering lights',
        status: 'assigned',
        workOrderId: 'wo-assigned',
      });
      await seed('damage_reports/pw-theirs', {
        reporterId: OTHER_FACULTY_UID,
        title: 'Leaking pipe',
        status: 'assigned',
        workOrderId: 'wo-unassigned',
      });
      await assertSucceeds(asPersonnel().doc('damage_reports/pw-mine').get());
      await assertFails(asPersonnel().doc('damage_reports/pw-theirs').get());
      await assertFails(asPersonnel().doc('damage_reports/rep-faculty').get());
    });
  });

  describe('tasks', () => {
    it('personnel list their own tasks, not everyone’s', async () => {
      await assertSucceeds(
        asPersonnel()
          .collection('tasks')
          .where('assignedTo', '==', PERSONNEL_UID)
          .get(),
      );
      await assertFails(asPersonnel().collection('tasks').get());
    });

    it('personnel tick their task and add proof, nothing else', async () => {
      await seedTask('pt-own');
      await assertSucceeds(
        asPersonnel().doc('tasks/pt-own').update({
          status: 'completed',
          completedAt: serverNow(),
          proofPhotoUrls: ['https://example.test/proof.jpg'],
          updatedAt: serverNow(),
        }),
      );
      await assertFails(
        asPersonnel().doc('tasks/pt-own').update({ title: 'Something easier' }),
      );
      await assertFails(
        asPersonnel().doc('tasks/pt-own').update({ assignedTo: ADMIN_UID }),
      );
    });

    it('personnel cannot touch, add or delete someone else’s task', async () => {
      await seedTask('pt-other', { assignedTo: 'someone-else' });
      await assertFails(asPersonnel().doc('tasks/pt-other').get());
      await assertFails(
        asPersonnel().doc('tasks/pt-other').update({ status: 'completed' }),
      );
      await assertFails(asPersonnel().doc('tasks/pt-own-new').set({
        workOrderId: 'wo-assigned',
        title: 'Self-assigned',
        assignedTo: PERSONNEL_UID,
        status: 'pending',
      }));
      await seedTask('pt-delete');
      await assertFails(asPersonnel().doc('tasks/pt-delete').delete());
      await assertSucceeds(asAdmin().doc('tasks/pt-delete').delete());
    });
  });

  describe('materials used', () => {
    const used = (db, workOrderId, itemId = 'inv-led') =>
      db.doc(`work_orders/${workOrderId}/materials_used/${itemId}`);

    it('the technician records materials on their open work', async () => {
      await seedWorkOrder('pm-pending', { status: 'pending' });
      await seedWorkOrder('pm-open');
      await assertSucceeds(used(asPersonnel(), 'pm-pending').set(material()));
      await assertSucceeds(used(asPersonnel(), 'pm-open').set(material()));
      await assertSucceeds(
        used(asPersonnel(), 'pm-open').set(material({ quantityUsed: 3 })),
      );
      await assertSucceeds(used(asPersonnel(), 'pm-open').get());
      await assertSucceeds(used(asAdmin(), 'pm-open').get());
      await assertSucceeds(used(asPersonnel(), 'pm-open').delete());
    });

    it('not once the work is submitted or closed', async () => {
      for (const status of ['forReview', 'completed', 'cancelled']) {
        const id = `pm-${status}`;
        await seedWorkOrder(id, { status });
        await seed(`work_orders/${id}/materials_used/inv-led`, {
          ...material(),
          recordedAt: firebase.firestore.Timestamp.now(),
        });
        await assertFails(used(asPersonnel(), id, 'inv-other').set(material()));
        await assertFails(
          used(asPersonnel(), id).set(material({ quantityUsed: 9 })),
        );
        await assertFails(used(asPersonnel(), id).delete());
      }
    });

    it('not on work assigned to someone else', async () => {
      await assertFails(used(asPersonnel(), 'wo-unassigned').set(material()));
      await assertFails(used(asPersonnel(), 'wo-unassigned').get());
      await assertFails(used(asFaculty(), 'wo-assigned').get());
    });

    it('a record is the technician’s own, stamped now, for a real amount', async () => {
      await seedWorkOrder('pm-shape');
      const doc = used(asPersonnel(), 'pm-shape');
      await assertFails(doc.set(material({ recordedBy: ADMIN_UID })));
      await assertFails(
        doc.set(
          material({
            recordedAt: firebase.firestore.Timestamp.fromDate(new Date(2020, 0, 1)),
          }),
        ),
      );
      await assertFails(doc.set(material({ quantityUsed: 0 })));
      await assertFails(doc.set(material({ quantityUsed: '2' })));
      await assertFails(doc.set(material({ unitCost: 120 })));
    });
  });

  describe('accomplishment reports', () => {
    it('a technician may ask whether a report id is taken', async () => {
      await assertSucceeds(
        asPersonnel().doc('accomplishment_reports/pa-not-yet').get(),
      );
    });

    it('is filed in the same write that submits the work', async () => {
      await seedWorkOrder('pa-file');
      await seed('work_orders/pa-file/materials_used/inv-led', {
        ...material(),
        recordedAt: firebase.firestore.Timestamp.now(),
      });
      const db = asPersonnel();
      const batch = db.batch();
      batch.update(db.doc('work_orders/pa-file'), {
        status: 'forReview',
        updatedAt: serverNow(),
      });
      batch.delete(db.doc('work_orders/pa-file/materials_used/inv-led'));
      batch.set(
        db.doc('accomplishment_reports/pa-file'),
        accomplishment('pa-file', {
          materialsUsed: [
            { inventoryItemId: 'inv-led', itemName: 'LED Bulbs', quantityUsed: 2 },
          ],
          inventoryDeducted: true,
        }),
      );
      await assertSucceeds(batch.commit());
      await assertSucceeds(
        asPersonnel().doc('accomplishment_reports/pa-file').get(),
      );
    });

    it('not without submitting the work, nor for someone else’s', async () => {
      await seedWorkOrder('pa-alone');
      await assertFails(
        asPersonnel()
          .doc('accomplishment_reports/pa-alone')
          .set(accomplishment('pa-alone')),
      );
      await seedWorkOrder('pa-theirs', { assignedPersonnelIds: ['someone-else'] });
      await assertFails(
        submit(asPersonnel(), 'pa-theirs', 'pa-theirs', accomplishment('pa-theirs')),
      );
      await seedWorkOrder('pa-as-other');
      await assertFails(
        submit(
          asPersonnel(),
          'pa-as-other',
          'pa-as-other',
          accomplishment('pa-as-other', { submittedBy: 'someone-else' }),
        ),
      );
    });

    it('says whether stock was deducted, and is unreviewed', async () => {
      await seedWorkOrder('pa-deducted');
      await assertFails(
        submit(
          asPersonnel(),
          'pa-deducted',
          'pa-deducted',
          accomplishment('pa-deducted', {
            materialsUsed: [
              { inventoryItemId: 'inv-led', itemName: 'LED Bulbs', quantityUsed: 2 },
            ],
            inventoryDeducted: false,
          }),
        ),
      );
      await assertFails(
        submit(
          asPersonnel(),
          'pa-deducted',
          'pa-deducted',
          accomplishment('pa-deducted', { inventoryDeducted: true }),
        ),
      );
      await assertFails(
        submit(
          asPersonnel(),
          'pa-deducted',
          'pa-deducted',
          accomplishment('pa-deducted', {
            reviewedBy: ADMIN_UID,
            reviewedAt: serverNow(),
          }),
        ),
      );
    });

    it('only the administrator reviews it, and nobody deletes it', async () => {
      await seedWorkOrder('pa-review', { status: 'forReview' });
      await seed('accomplishment_reports/pa-review', {
        ...accomplishment('pa-review'),
        submittedAt: firebase.firestore.Timestamp.now(),
      });
      const path = 'accomplishment_reports/pa-review';
      await assertFails(
        asPersonnel().doc(path).update({
          reviewedBy: PERSONNEL_UID,
          reviewedAt: serverNow(),
        }),
      );
      await assertFails(
        asPersonnel().doc(path).update({ completionNotes: 'Rewritten.' }),
      );
      await assertSucceeds(
        asAdmin().doc(path).update({
          reviewedBy: ADMIN_UID,
          reviewedAt: serverNow(),
        }),
      );
      await assertFails(asAdmin().doc(path).delete());
    });

    it('personnel list their own reports, not everyone’s', async () => {
      await assertSucceeds(
        asPersonnel()
          .collection('accomplishment_reports')
          .where('workOrderId', '==', 'wo-assigned')
          .where('submittedBy', '==', PERSONNEL_UID)
          .get(),
      );
      await assertFails(
        asPersonnel()
          .collection('accomplishment_reports')
          .where('workOrderId', '==', 'wo-assigned')
          .get(),
      );
    });
  });

  describe('tool loans', () => {
    it('personnel list their own loans, not everyone’s', async () => {
      await assertSucceeds(
        asPersonnel()
          .collection('tool_loans')
          .where('borrowedBy', '==', PERSONNEL_UID)
          .where('returnedAt', '==', null)
          .get(),
      );
      await assertFails(asPersonnel().collection('tool_loans').get());
    });
  });
});

describe('inventory management (6.A–6.C)', () => {
  const seed = (path, data) =>
    testEnv.withSecurityRulesDisabled((context) =>
      context.firestore().doc(path).set(data),
    );

  const seedWorkOrder = (id, data = {}) =>
    seed(`work_orders/${id}`, {
      reportIds: ['rep-faculty'],
      title: 'Repair ceiling fan',
      description: 'Replace bearing.',
      category: 'electrical',
      priority: 'high',
      status: 'inProgress',
      assignedPersonnelIds: [PERSONNEL_UID],
      createdBy: ADMIN_UID,
      ...data,
    });

  /// A request as the repository files it.
  const materialRequest = (workOrderId, overrides = {}) => ({
    workOrderId,
    requestedBy: PERSONNEL_UID,
    requestedByName: 'Marcus Wright',
    items: [
      {
        inventoryItemId: 'inv-led',
        itemName: 'LED Bulbs',
        quantity: 4,
        unitOfMeasurement: 'units',
      },
    ],
    status: 'pending',
    note: 'Two more fixtures are out.',
    adminNote: null,
    reviewedBy: null,
    reviewedAt: null,
    createdAt: serverNow(),
    updatedAt: serverNow(),
    ...overrides,
  });

  const seedRequest = async (id, workOrderId, data = {}) =>
    seed(`material_requests/${id}`, {
      ...materialRequest(workOrderId),
      createdAt: firebase.firestore.Timestamp.now(),
      updatedAt: firebase.firestore.Timestamp.now(),
      ...data,
    });

  /// The review fields an approval or decline writes.
  const review = (status, overrides = {}) => ({
    status,
    adminNote: null,
    reviewedBy: ADMIN_UID,
    reviewedAt: serverNow(),
    updatedAt: serverNow(),
    ...overrides,
  });

  describe('material requests', () => {
    it('a technician requests materials for their own open work', async () => {
      await seedWorkOrder('mr-open');
      await assertSucceeds(
        asPersonnel()
          .doc('material_requests/mr-ok')
          .set(materialRequest('mr-open')),
      );
      await assertSucceeds(
        asPersonnel().doc('material_requests/mr-not-yet').get(),
      );
    });

    it('not for someone else’s work, closed work, or as someone else', async () => {
      await seedWorkOrder('mr-theirs', { assignedPersonnelIds: ['someone-else'] });
      await seedWorkOrder('mr-closed', { status: 'forReview' });
      await seedWorkOrder('mr-mine');
      const db = asPersonnel();
      await assertFails(
        db.doc('material_requests/mr-1').set(materialRequest('mr-theirs')),
      );
      await assertFails(
        db.doc('material_requests/mr-2').set(materialRequest('mr-closed')),
      );
      await assertFails(
        db
          .doc('material_requests/mr-3')
          .set(materialRequest('mr-mine', { requestedBy: 'someone-else' })),
      );
      await assertFails(
        asFaculty()
          .doc('material_requests/mr-4')
          .set(materialRequest('mr-mine', { requestedBy: FACULTY_UID })),
      );
    });

    it('arrives pending and unreviewed, stamped now, with materials', async () => {
      await seedWorkOrder('mr-shape');
      const db = asPersonnel();
      await assertFails(
        db
          .doc('material_requests/mr-5')
          .set(materialRequest('mr-shape', { status: 'approved' })),
      );
      await assertFails(
        db
          .doc('material_requests/mr-6')
          .set(materialRequest('mr-shape', { adminNote: 'Approved by me.' })),
      );
      await assertFails(
        db.doc('material_requests/mr-7').set(
          materialRequest('mr-shape', {
            createdAt: firebase.firestore.Timestamp.fromDate(new Date(2020, 0, 1)),
          }),
        ),
      );
      await assertFails(
        db.doc('material_requests/mr-8').set(materialRequest('mr-shape', { items: [] })),
      );
      await assertFails(
        db
          .doc('material_requests/mr-9')
          .set(materialRequest('mr-shape', { priority: 'urgent' })),
      );
    });

    it('a technician lists their own requests only', async () => {
      await assertSucceeds(
        asPersonnel()
          .collection('material_requests')
          .where('workOrderId', '==', 'wo-assigned')
          .where('requestedBy', '==', PERSONNEL_UID)
          .get(),
      );
      await assertFails(
        asPersonnel()
          .collection('material_requests')
          .where('workOrderId', '==', 'wo-assigned')
          .get(),
      );
      await assertSucceeds(
        asAdmin().collection('material_requests').orderBy('createdAt', 'desc').get(),
      );
    });

    it('only an administrator reviews one, once; declining needs a reason', async () => {
      await seedWorkOrder('mr-review');
      await seedRequest('mr-approve', 'mr-review');
      await seedRequest('mr-decline', 'mr-review');
      const path = 'material_requests/mr-approve';

      await assertFails(asPersonnel().doc(path).update(review('approved')));
      await assertFails(
        asAdmin()
          .doc('material_requests/mr-decline')
          .update(review('declined')),
      );
      await assertSucceeds(
        asAdmin()
          .doc('material_requests/mr-decline')
          .update(review('declined', { adminNote: 'Use what is on the job.' })),
      );
      await assertFails(
        asAdmin().doc(path).update({ ...review('approved'), items: [] }),
      );
      await assertSucceeds(asAdmin().doc(path).update(review('approved')));
      await assertFails(asAdmin().doc(path).update(review('declined', {
        adminNote: 'Changed my mind.',
      })));
      await assertFails(asAdmin().doc(path).delete());
    });
  });

  describe('pre-assigned materials', () => {
    const allocation = {
      itemName: 'LED Bulbs',
      quantity: 4,
      unitOfMeasurement: 'units',
      allocatedBy: ADMIN_UID,
      allocatedAt: serverNow(),
    };

    it('an administrator sets them; the assigned technician reads them', async () => {
      await seedWorkOrder('pa-mine');
      await seedWorkOrder('pa-theirs', { assignedPersonnelIds: ['someone-else'] });
      const mine = 'work_orders/pa-mine/materials_allocated/inv-led';
      await assertSucceeds(asAdmin().doc(mine).set(allocation));
      await assertSucceeds(asPersonnel().doc(mine).get());
      await assertFails(asPersonnel().doc(mine).set({ ...allocation, quantity: 40 }));
      await assertFails(asPersonnel().doc(mine).delete());

      const theirs = 'work_orders/pa-theirs/materials_allocated/inv-led';
      await assertSucceeds(asAdmin().doc(theirs).set(allocation));
      await assertFails(asPersonnel().doc(theirs).get());
      await assertFails(asFaculty().doc(mine).get());
    });
  });

  describe('tools from the console', () => {
    const loan = (borrowedBy) => ({
      toolId: 'tool-console',
      toolName: 'Fluke Multimeter 179',
      borrowedBy,
      workOrderId: null,
      borrowedAt: firebase.firestore.Timestamp.now(),
      expectedReturnAt: null,
      returnedAt: null,
      conditionOnBorrow: 'good',
      conditionOnReturn: null,
      notes: null,
    });

    it('an administrator checks a tool out to a technician, not to anyone', async () => {
      await assertSucceeds(
        asAdmin().collection('tool_loans').add(loan(PERSONNEL_UID)),
      );
      await assertFails(asAdmin().collection('tool_loans').add(loan(FACULTY_UID)));
      await assertFails(asPersonnel().collection('tool_loans').add(loan(ADMIN_UID)));
      await assertSucceeds(
        asPersonnel().collection('tool_loans').add(loan(PERSONNEL_UID)),
      );
    });
  });

  describe('materials, rooms and equipment', () => {
    it('only an administrator adds or edits them', async () => {
      const item = {
        name: 'Wall Socket Plate',
        category: 'Electrical',
        quantityAvailable: 0,
        unitOfMeasurement: 'pcs',
        storageLocation: 'Store B',
        qrCode: 'INV-PLATE',
        minimumThreshold: 5,
        unitCost: 85,
      };
      await assertSucceeds(asAdmin().doc('inventory_items/inv-plate').set(item));
      await assertFails(asPersonnel().doc('inventory_items/inv-plate-2').set(item));
      await assertFails(
        asPersonnel().doc('inventory_items/inv-plate').update({ unitCost: 1 }),
      );

      const room = {
        name: 'Annex',
        buildingName: 'Annex',
        qrCode: 'FAC-ANNEX',
        isActive: true,
      };
      await assertSucceeds(asAdmin().doc('facilities/fac-annex').set(room));
      await assertFails(asPersonnel().doc('facilities/fac-annex-2').set(room));
      await assertFails(
        asFaculty().doc('facilities/fac-annex').update({ isActive: false }),
      );
    });
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
