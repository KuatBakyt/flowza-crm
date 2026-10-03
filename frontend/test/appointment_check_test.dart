import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowza/core/api.dart';
import 'package:flowza/core/appointment_check.dart';

import 'helpers.dart';

void main() {
  for (final accept in [false, true]) {
    testWidgets('Outside hours requires explicit choice: $accept', (t) async {
      bool? outcome;
      final api = ApiClient(
        MemoryTokens(),
        adapter: JsonAdapter(
          (options) async =>
              (200, {'available': true, 'within_working_hours': false}),
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  outcome = await checkAppointment(
                    context,
                    api,
                    'master',
                    DateTime(2026, 10, 5, 20),
                    DateTime(2026, 10, 5, 21),
                  );
                },
                child: const Text('Проверить'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Проверить'));
      await t.pumpAndSettle();
      expect(outcome, isNull);
      expect(find.text('Вне рабочего графика'), findsOneWidget);
      await t.tap(
        find.text(accept ? 'Всё равно назначить' : 'Выбрать другое время'),
      );
      await t.pumpAndSettle();
      expect(outcome, accept);
    });
  }
  testWidgets('Occupied time cannot be overridden', (t) async {
    Object? error;
    final api = ApiClient(
      MemoryTokens(),
      adapter: JsonAdapter(
        (options) async =>
            (200, {'available': false, 'within_working_hours': false}),
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                try {
                  await checkAppointment(
                    context,
                    api,
                    'master',
                    DateTime(2026, 10, 5, 20),
                    DateTime(2026, 10, 5, 21),
                  );
                } catch (e) {
                  error = e;
                }
              },
              child: const Text('Проверить'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Проверить'));
    await t.pumpAndSettle();
    expect(error, isNotNull);
    expect(find.text('Всё равно назначить'), findsNothing);
  });
}
