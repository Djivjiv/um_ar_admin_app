import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/data/repositories/kiosk_repository.dart';
import 'package:um_ar_admin/data/repositories/repository_exception.dart';
import 'package:um_ar_admin/domain/models/kiosk_settings_model.dart';
import 'package:um_ar_admin/presentation/screens/kiosk/kiosk_management_screen.dart';

import 'support/fake_postgrest.dart';

const _savedPin = '246810';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

void main() {
  late FakePostgrest db;

  Map<String, dynamic> settingsRow() => db.tables['kiosk_settings']!.single;

  setUp(() {
    db = FakePostgrest()..install();
    db.tables['kiosk_settings'] = [
      {'id': 1, 'welcome_message': 'Hi', 'exit_pin': null},
    ];
  });
  tearDown(FakePostgrest.uninstall);

  group('PIN rule', () {
    test('4 to 8 digits, typed the same twice', () {
      expect(exitPinProblem('1234', '1234'), isNull);
      expect(exitPinProblem('12345678', '12345678'), isNull);
      expect(exitPinProblem('123', '123'), 'Use 4 to 8 digits.');
      expect(exitPinProblem('123456789', '123456789'), 'Use 4 to 8 digits.');
      expect(exitPinProblem('12a4', '12a4'), 'Use 4 to 8 digits.');
      expect(exitPinProblem(' 1234', ' 1234'), 'Use 4 to 8 digits.');
      expect(exitPinProblem('1234', '1235'), 'The two PINs do not match.');
    });
  });

  group('KioskSettingsModel', () {
    test('knows a PIN is set without keeping it', () {
      final s = KioskSettingsModel.fromJson({'id': 1, 'exit_pin': _savedPin});
      expect(s.hasExitPin, isTrue);
      expect(KioskSettingsModel.fromJson({'id': 1}).hasExitPin, isFalse);
      expect(KioskSettingsModel.fromJson({'exit_pin': ' '}).hasExitPin,
          isFalse);
    });

    test('never writes exit_pin, so saving settings keeps the PIN', () {
      final s = KioskSettingsModel.fromJson({'id': 1, 'exit_pin': _savedPin});
      expect(s.toJson().containsKey('exit_pin'), isFalse);
      expect(s.toJson().values, isNot(contains(_savedPin)));
    });
  });

  group('KioskRepository.setExitPin', () {
    test('writes only the PIN and the time on the settings row', () async {
      await KioskRepository().setExitPin('1357', settingsId: 1);
      expect(settingsRow()['exit_pin'], '1357');
      expect(settingsRow()['welcome_message'], 'Hi');
      expect(settingsRow()['updated_at'], isNotNull);
    });

    test('creates the row when there is none yet', () async {
      db.tables['kiosk_settings'] = [];
      await KioskRepository().setExitPin('1357');
      expect(settingsRow()['exit_pin'], '1357');
      expect(settingsRow()['idle_timeout_seconds'], 120);
    });

    test('rejects a bad PIN without asking the server', () async {
      for (final pin in const ['123', '123456789', 'abcd']) {
        await expectLater(KioskRepository().setExitPin(pin, settingsId: 1),
            throwsA(isA<RepositoryException>()));
      }
      expect(db.requests, isEmpty);
    });

    test('a write blocked by Row Level Security fails, without the PIN',
        () async {
      db.rlsBlockedWrites.add('kiosk_settings');
      await expectLater(
        KioskRepository().setExitPin('97531', settingsId: 1),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('changed nothing'))
            .having((e) => e.message, 'message', isNot(contains('97531')))
            .having((e) => e.cause, 'cause', isNull)),
      );
    });

    test('a missing exit_pin column says which file to run', () async {
      db.failing.add('PATCH kiosk_settings');
      db.failureCode = 'PGRST204';
      db.failureMessage =
          "Could not find the 'exit_pin' column of 'kiosk_settings'";
      await expectLater(
        KioskRepository().setExitPin('97531', settingsId: 1),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', contains('kiosk_settings.sql'))
            .having((e) => e.cause, 'cause', isNull)),
      );
    });

    test('any other database error never carries the PIN', () async {
      db.failing.add('PATCH kiosk_settings');
      db.failureMessage = 'Failing row contains (1, 97531)';
      await expectLater(
        KioskRepository().setExitPin('97531', settingsId: 1),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', isNot(contains('97531')))
            .having((e) => e.cause, 'cause', isNull)),
      );
    });

    test('saving the other settings leaves the PIN alone', () async {
      settingsRow()['exit_pin'] = _savedPin;
      final repo = KioskRepository();
      final s = await repo.getSettings();
      await repo.updateSettings(s.copyWith(welcomeMessage: 'Hello'));
      expect(settingsRow()['exit_pin'], _savedPin);
      expect(settingsRow()['welcome_message'], 'Hello');
    });
  });

  group('Kiosk Management exit PIN card', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: KioskManagementScreen())));
      await settle(tester);
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);

    Future<void> typeAndSave(
        WidgetTester tester, String pin, String confirm) async {
      await tester.enterText(field('New PIN (4 to 8 digits)'), pin);
      await tester.enterText(field('Confirm PIN'), confirm);
      await tester.ensureVisible(find.text('Set PIN'));
      await tester.tap(find.text('Set PIN'));
      await settle(tester);
    }

    testWidgets('says no PIN is set, and hides what is typed', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('No PIN is set'), findsOneWidget);
      for (final label in const ['New PIN (4 to 8 digits)', 'Confirm PIN']) {
        final editable = tester.widget<EditableText>(
            find.descendant(of: field(label), matching: find.byType(EditableText)));
        expect(editable.obscureText, isTrue, reason: label);
      }
    });

    testWidgets('never shows a saved PIN', (tester) async {
      settingsRow()['exit_pin'] = _savedPin;
      await pumpScreen(tester);
      expect(find.textContaining('A PIN is set'), findsOneWidget);
      expect(find.textContaining(_savedPin), findsNothing);
      expect(find.text('Change PIN'), findsOneWidget);
    });

    testWidgets('checks the PIN before saving', (tester) async {
      await pumpScreen(tester);
      await typeAndSave(tester, '12', '12');
      expect(find.text('Use 4 to 8 digits.'), findsWidgets);
      await typeAndSave(tester, '13579', '13578');
      expect(find.text('The two PINs do not match.'), findsOneWidget);
      expect(settingsRow()['exit_pin'], isNull);
      expect(db.requestCount('PATCH kiosk_settings'), 0);
    });

    testWidgets('saves, clears the fields and says a PIN is set',
        (tester) async {
      await pumpScreen(tester);
      await typeAndSave(tester, '13579', '13579');
      expect(settingsRow()['exit_pin'], '13579');
      expect(find.textContaining('A PIN is set'), findsOneWidget);
      expect(find.text('13579'), findsNothing, reason: 'fields are cleared');
    });

    testWidgets('a failed save shows Retry, which saves', (tester) async {
      await pumpScreen(tester);
      db.failing.add('PATCH kiosk_settings');
      await typeAndSave(tester, '13579', '13579');
      expect(find.textContaining('Failed to save the exit PIN'),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching: find.textContaining('13579')),
          findsNothing,
          reason: 'the error never shows the PIN');

      db.failing.clear();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(settingsRow()['exit_pin'], '13579');
    });
  });
}
