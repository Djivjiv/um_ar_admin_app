import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/building_repository.dart';
import 'package:um_ar_admin/domain/models/building_model.dart';
import 'package:um_ar_admin/presentation/screens/buildings/building_form.dart';

import 'support/fake_postgrest.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

void main() {
  late FakePostgrest db;

  Object? linkOf(String id) => db.tables['indoor_nodes']!
      .firstWhere((n) => n['id'] == id)['linked_room_id'];
  Map<String, dynamic> building() => db.tables['buildings']!.single;

  setUp(() {
    db = FakePostgrest()..install();
    db.tables['buildings'] = [
      {
        'id': 7,
        'name': 'Main',
        'is_active': true,
        'display_name': 'MAIN',
        'label_lat': 7.1,
        'label_lng': 125.6,
      },
    ];
    db.tables['rooms'] = [
      {'id': 1, 'roomname': 'Lab', 'building_id': 7, 'is_active': true},
      {'id': 2, 'roomname': 'Other', 'building_id': 8, 'is_active': true},
    ];
    db.tables['facilities'] = [
      {'id': 3, 'roomname': 'Clinic', 'building_id': 7, 'is_active': true},
    ];
    db.tables['indoor_nodes'] = [
      {'id': 'to-room', 'linked_room_id': 1, 'linked_table': 'rooms'},
      {'id': 'to-facility', 'linked_room_id': 3, 'linked_table': 'facilities'},
      {'id': 'elsewhere', 'linked_room_id': 2, 'linked_table': 'rooms'},
    ];
  });
  tearDown(FakePostgrest.uninstall);

  group('BuildingRepository', () {
    const inactive = BuildingModel(id: 7, name: 'Main', isActive: false);
    const active = BuildingModel(id: 7, name: 'Main');

    test('linkedNodeCount counts nodes on its rooms and facilities', () async {
      expect(await BuildingRepository().linkedNodeCount(7), 2);
      expect(await BuildingRepository().linkedNodeCount(99), 0);
    });

    test('saving it inactive unlinks its rooms and facilities', () async {
      await BuildingRepository().update(inactive);
      expect(building()['is_active'], isFalse);
      expect(linkOf('to-room'), isNull);
      expect(linkOf('to-facility'), isNull);
      expect(linkOf('elsewhere'), 2, reason: 'room 2 is in another building');
    });

    test('saving it active touches no links', () async {
      await BuildingRepository().update(active);
      expect(linkOf('to-room'), 1);
      expect(db.requestCount('PATCH indoor_nodes'), 0);
    });

    test('a failed save puts the links back', () async {
      db.failing.add('PATCH buildings');
      await expectLater(
          BuildingRepository().update(inactive), throwsA(isA<Object>()));
      expect(linkOf('to-room'), 1);
      expect(linkOf('to-facility'), 3);
      expect(building()['is_active'], isTrue);
    });
  });

  group('Building form', () {
    Future<void> pumpForm(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final existing = BuildingModel.fromJson(building());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: BuildingForm(building: existing)),
        ),
      ));
      await settle(tester);
    }

    Future<void> switchOffAndSave(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(SwitchListTile, 'Active'));
      await tester.pump();
      await tester.tap(find.text('Save Changes'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('deactivating warns, then unlinks', (tester) async {
      await pumpForm(tester);
      await switchOffAndSave(tester);
      expect(find.textContaining('2 floor plan nodes point'), findsOneWidget);

      await tester.tap(find.text('Unlink and deactivate'));
      await settle(tester);
      expect(building()['is_active'], isFalse);
      expect(linkOf('to-room'), isNull);
      expect(linkOf('to-facility'), isNull);
    });

    testWidgets('cancelling the warning changes nothing', (tester) async {
      await pumpForm(tester);
      await switchOffAndSave(tester);
      await tester.tap(find.text('Cancel').last);
      await settle(tester);
      expect(building()['is_active'], isTrue);
      expect(linkOf('to-room'), 1);
      expect(db.requestCount('PATCH buildings'), 0);
    });

    testWidgets('saving keeps the Campus Map name and label position',
        (tester) async {
      await pumpForm(tester);
      await tester.tap(find.text('Save Changes'));
      await settle(tester);
      expect(building()['display_name'], 'MAIN');
      expect(building()['label_lat'], 7.1);
      expect(building()['label_lng'], 125.6);
    });
  });
}
