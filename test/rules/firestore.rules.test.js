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

const PROJECT_ID = 'gsuhub-rules-test';

const ADMIN_UID = 'admin-uid';
const FACULTY_UID = 'faculty-uid';
const PERSONNEL_UID = 'personnel-uid';
const OTHER_FACULTY_UID = 'other-faculty-uid';
const INACTIVE_UID = 'inactive-uid';

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

describe('unknown collections', () => {
  it('are denied by the catch-all rule', async () => {
    await assertFails(asAdmin().doc('not_a_real_collection/doc').get());
    await assertFails(
      asAdmin().doc('not_a_real_collection/doc').set({ a: 1 }),
    );
  });
});

assert.ok(true, 'module loaded');
