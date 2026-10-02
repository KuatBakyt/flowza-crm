import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flowza/main.dart';
import 'package:flowza/core/api.dart';
import 'package:flowza/core/router.dart';
import 'package:flowza/features/auth/presentation/auth.dart';

import 'helpers.dart';

Future<ProviderContainer> boot(
  WidgetTester tester,
  FixtureServer server, {
  bool signed = true,
}) async {
  final tokens = MemoryTokens();
  if (signed) await tokens.save('a', 'r');
  final container = ProviderContainer(
    overrides: [
      apiProvider.overrideWithValue(
        ApiClient(tokens, adapter: JsonAdapter(server.call)),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const FlowzaApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  testWidgets('Profile has immutable identity and a mobile weekly schedule', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = await boot(t, FixtureServer());
    addTearDown(c.dispose);
    c.read(routerProvider).go('/profile');
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Рабочий график'), findsOneWidget);
    expect(find.text('Понедельник'), findsOneWidget);
    expect(find.text('Воскресенье'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(8));
    await t.tap(find.byType(Switch).last);
    await t.pumpAndSettle();
    expect(find.text('Не работаю'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('Login validates missing identity and password', (t) async {
    final c = await boot(t, FixtureServer(), signed: false);
    addTearDown(c.dispose);
    await t.tap(find.text('Войти'));
    await t.pumpAndSettle();
    expect(find.text('Введите телефон или email'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
  });
  for (final mode in ['empty', 'error', 'data']) {
    testWidgets('Orders $mode state', (t) async {
      final server = FixtureServer()
        ..empty = mode == 'empty'
        ..ordersStatus = mode == 'error' ? 500 : 200;
      final c = await boot(t, server);
      addTearDown(c.dispose);
      c.read(routerProvider).go('/orders');
      await t.pumpAndSettle();
      expect(
        find.text(
          mode == 'empty'
              ? 'Заказов пока нет'
              : mode == 'error'
              ? 'Ошибка загрузки'
              : 'Поклейка обоев',
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('Order detail confirms through API', (t) async {
    final server = FixtureServer();
    final c = await boot(t, server);
    addTearDown(c.dispose);
    c.read(routerProvider).go('/orders/o1');
    await t.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Подтвердить заказ');
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    await t.tap(button);
    await t.pumpAndSettle();
    expect(server.actions, ['confirm']);
    expect(find.text('Подтверждён'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('Responsive dashboard ${size.width}', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = await boot(t, FixtureServer());
      addTearDown(c.dispose);
      expect(
        find.text('Flowza'),
        size.width > 1000 ? findsOneWidget : findsNothing,
      );
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('Live refresh pauses in background and resumes immediately', (
    t,
  ) async {
    final c = await boot(t, FixtureServer());
    addTearDown(c.dispose);
    final initial = c.read(liveRevisionProvider);
    await t.pump(const Duration(seconds: 30));
    expect(c.read(liveRevisionProvider), initial + 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(seconds: 60));
    expect(c.read(liveRevisionProvider), initial + 1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(c.read(liveRevisionProvider), initial + 2);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  testWidgets('Order link is restored after sign-in', (t) async {
    final c = await boot(t, FixtureServer(), signed: false);
    addTearDown(c.dispose);
    c.read(routerProvider).go('/orders/o1');
    await t.pumpAndSettle();
    expect(find.text('Войти'), findsWidgets);
    final login = c
        .read(authProvider.notifier)
        .login('+77000000000', 'password');
    await t.pumpAndSettle();
    await login;
    await t.pumpAndSettle();
    expect(find.text('Карточка заказа'), findsOneWidget);
  });
}
