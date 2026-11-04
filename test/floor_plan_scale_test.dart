import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_admin/data/repositories/indoor_link_cleanup.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/domain/models/floor_plan_model.dart';

import 'support/fake_postgrest.dart';

void main() {
  group('FloorPlanModel scale', () {
    test('a missing scale is not calibrated and never guessed', () {
      final p = FloorPlanModel.fromJson({'id': 1});
      expect(p.metersPerPixel, isNull);
      expect(p.isScaleCalibrated, isFalse);
      expect(p.scaleLabel, 'not calibrated');
      expect(p.effectiveMetersPerPixel, kDefaultMetersPerPixel);
    });

    test('zero or negative stored scales count as not calibrated', () {
      expect(FloorPlanModel.fromJson({'meters_per_pixel': 0}).metersPerPixel,
          isNull);
      expect(
          FloorPlanModel.fromJson({'meters_per_pixel': -1}).metersPerPixel,
          isNull);
    });

    test('toJson leaves an uncalibrated scale out of the save', () {
      final json = FloorPlanModel.fromJson({'id': 1, 'building_id': 2})
          .copyWith(floorName: 'Ground')
          .toJson();
      expect(json.containsKey('meters_per_pixel'), isFalse);
      expect(json['floor_name'], 'Ground');
    });

    test('a calibrated scale round-trips', () {
      final p = FloorPlanModel.fromJson({'meters_per_pixel': '0.032'});
      expect(p.metersPerPixel, 0.032);
      expect(p.scaleLabel, '0.032 m/px');
      expect(p.toJson()['meters_per_pixel'], 0.032);
    });

    test('the default 0.05 is flagged, not treated as calibrated', () {
      final p = FloorPlanModel.fromJson({'meters_per_pixel': 0.05});
      expect(p.metersPerPixel, 0.05);
      expect(p.isScaleCalibrated, isFalse);
      expect(p.scaleLabel, '0.05 m/px (default)');
      expect(p.toJson()['meters_per_pixel'], 0.05);
    });

    test('optional scale field: empty is allowed, bad input is not', () {
      expect(validateOptionalMetersPerPixel(''), isNull);
      expect(validateOptionalMetersPerPixel('  '), isNull);
      expect(validateOptionalMetersPerPixel('0.05'), isNull);
      expect(validateOptionalMetersPerPixel('0'), isNotNull);
      expect(validateOptionalMetersPerPixel('abc'), isNotNull);
      expect(validateOptionalMetersPerPixel('11'), isNotNull);
      expect(parseOptionalMetersPerPixel(''), isNull);
      expect(parseOptionalMetersPerPixel(' 0.04 '), 0.04);
    });
  });

  group('saveScale', () {
    late FakePostgrest db;

    setUp(() {
      db = FakePostgrest()..install();
      db.tables['building_floors'] = [
        {
          'id': 1,
          'building_id': 2,
          'image_url': 'keep.png',
          'meters_per_pixel': 0.05,
        },
      ];
    });
    tearDown(FakePostgrest.uninstall);

    test('writes the value and returns what a reload found', () async {
      final saved = await FloorPlanRepository().saveScale(1, 0.032);
      expect(saved.metersPerPixel, 0.032);
      expect(saved.isScaleCalibrated, isTrue);
      expect(db.tables['building_floors']!.single['meters_per_pixel'], 0.032);
      expect(db.requests, ['PATCH building_floors', 'GET building_floors']);
    });

    test('writes only the scale column', () async {
      db.onRequest = (key) {
        if (key == 'PATCH building_floors') {
          db.tables['building_floors']!.single['image_url'] = 'newer.png';
        }
      };
      await FloorPlanRepository().saveScale(1, 0.032);
      expect(db.tables['building_floors']!.single['image_url'], 'newer.png');
    });

    test('fails when the reload shows a different value', () async {
      db.onRequest = (key) {
        if (key == 'GET building_floors') {
          db.tables['building_floors']!.single['meters_per_pixel'] = 0.05;
        }
      };
      await expectLater(
        FloorPlanRepository().saveScale(1, 0.032),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('reloaded with'))),
      );
    });

    test('fails when Row Level Security blocks the write', () async {
      db.rlsBlockedWrites.add('building_floors');
      await expectLater(
        FloorPlanRepository().saveScale(1, 0.032),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('changed nothing'))),
      );
    });

    test('fails for a floor plan that does not exist', () async {
      await expectLater(FloorPlanRepository().saveScale(99, 0.032),
          throwsA(isA<RepositoryException>()));
    });

    test('names a missing column', () async {
      db.failing.add('PATCH building_floors');
      db.failureMessage = 'column meters_per_pixel does not exist';
      await expectLater(
        FloorPlanRepository().saveScale(1, 0.032),
        throwsA(isA<RepositoryException>().having((e) => e.message, 'message',
            contains('floor_plan_pixel_scale.sql'))),
      );
    });
  });

  group('linkedTableFilter', () {
    test('rooms also match the legacy null linked_table', () {
      expect(linkedTableFilter(LinkedTable.rooms),
          'linked_table.eq.rooms,linked_table.is.null');
    });

    test('facilities match only facilities', () {
      expect(linkedTableFilter(LinkedTable.facilities),
          'linked_table.eq.facilities');
    });
  });
}
