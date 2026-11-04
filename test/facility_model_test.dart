import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/domain/models/facility_model.dart';

void main() {
  group('FacilityModel.isActive parsing', () {
    bool parse(Map<String, dynamic> json) =>
        FacilityModel.fromJson(json).isActive;

    test('reads a real boolean', () {
      expect(parse({'id': 1, 'is_active': true}), isTrue);
      expect(parse({'id': 1, 'is_active': false}), isFalse);
    });

    test('missing column defaults to active', () {
      // e.g. getByBuilding() selects only a few columns.
      expect(parse({'id': 1, 'roomname': 'Registrar'}), isTrue);
    });

    test('null defaults to active, matching the column default', () {
      expect(parse({'id': 1, 'is_active': null}), isTrue);
    });

    test('accepts string and numeric forms', () {
      expect(parse({'is_active': 'true'}), isTrue);
      expect(parse({'is_active': 't'}), isTrue);
      expect(parse({'is_active': '1'}), isTrue);
      expect(parse({'is_active': 1}), isTrue);
      expect(parse({'is_active': 'false'}), isFalse);
      expect(parse({'is_active': 'f'}), isFalse);
      expect(parse({'is_active': 0}), isFalse);
    });

    test('a constructed facility is active unless told otherwise', () {
      expect(const FacilityModel().isActive, isTrue);
      expect(const FacilityModel(isActive: false).isActive, isFalse);
    });
  });

  group('FacilityModel.facilityJson', () {
    test('writes is_active for both states', () {
      expect(const FacilityModel(isActive: true).facilityJson()['is_active'],
          isTrue);
      expect(const FacilityModel(isActive: false).facilityJson()['is_active'],
          isFalse);
    });

    test('round-trips through fromJson', () {
      final original = FacilityModel.fromJson({
        'id': 7,
        'roomname': 'Clinic',
        'building_id': 3,
        'floor': 1,
        'is_active': false,
        'description': ['First aid'],
      });
      final again = FacilityModel.fromJson(original.facilityJson());
      expect(again.isActive, isFalse);
      expect(again.roomname, 'Clinic');
      expect(again.description, ['First aid']);
    });

    test('is_active stays out of the facility_details payload', () {
      expect(const FacilityModel().detailsJson().containsKey('is_active'),
          isFalse);
    });
  });

  test('other fields still parse alongside is_active', () {
    final f = FacilityModel.fromJson({
      'id': '12',
      'roomname': 'Library',
      'building_id': 2,
      'is_active': false,
      'buildings': {'id': 2, 'name': 'PE Building'},
      'facility_details': [
        {'id': 5, 'office_hours': '8-5', 'services': ['Printing']},
      ],
    });
    expect(f.id, 12);
    expect(f.buildingName, 'PE Building');
    expect(f.officeHours, '8-5');
    expect(f.services, ['Printing']);
    expect(f.isActive, isFalse);
  });
}
