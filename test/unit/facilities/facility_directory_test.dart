import 'package:flutter_test/flutter_test.dart';
import 'package:gsuhub/features/facilities/presentation/facility_directory.dart';

import '../../support/fake_report_form_backend.dart';

/// The report form's Building and Room selects, derived from the
/// facilities (Objective 3.C).
void main() {
  test('groups rooms under their building, both in reading order', () {
    final directory = FacilityDirectory([
      fakeFacility(id: 'a', building: 'Science Building', room: 'Lab 10'),
      fakeFacility(id: 'b', building: 'Engineering Building', room: 'Room 9'),
      fakeFacility(id: 'c', building: 'Science Building', room: 'Lab 2'),
      fakeFacility(id: 'd', building: 'Engineering Building', room: 'Room 10'),
    ]);

    expect(directory.buildings, ['Engineering Building', 'Science Building']);
    expect(
      directory.roomsIn('Engineering Building').map((f) => f.roomIdentifier),
      ['Room 9', 'Room 10'],
      reason: 'numbers compare as numbers',
    );
    expect(directory.roomsIn('Science Building').map((f) => f.roomIdentifier), [
      'Lab 2',
      'Lab 10',
    ]);
  });

  test('leaves out retired facilities', () {
    final directory = FacilityDirectory([
      fakeFacility(
        id: 'a',
        building: 'Old Annex',
        room: 'Room 1',
        isActive: false,
      ),
      fakeFacility(id: 'b', building: 'Gymnasium', room: 'Main Court'),
    ]);

    expect(directory.buildings, ['Gymnasium']);
  });

  test('names a room-less facility after itself', () {
    final whole = fakeFacility(id: 'gym', building: 'Gymnasium');

    expect(FacilityDirectory.roomLabelOf(whole), 'Gymnasium');
  });

  test('answers an unknown building with no rooms', () {
    expect(FacilityDirectory(const []).roomsIn('Nowhere'), isEmpty);
    expect(FacilityDirectory(const []).isEmpty, isTrue);
  });
}
