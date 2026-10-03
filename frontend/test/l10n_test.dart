import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flowza/core/l10n.dart';
import 'package:flowza/core/translations.dart';
import 'package:flowza/core/router.dart';
import 'package:flowza/core/api.dart';
import 'package:flowza/main.dart';

import 'helpers.dart';

class MemoryLanguage implements LanguageStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String language) async {
    value = language;
  }
}

void main() {
  setUpAll(() async {
    for (final code in languageNames.keys) {
      await initializeDateFormatting(code);
    }
  });
  test('Complete catalogs, interpolation and Russian default', () {
    final store = MemoryLanguage();
    final controller = LanguageController(store, 'invalid');
    expect(controller.state, 'ru');
    controller.dispose();
    for (final entry in translations.entries) {
      expect(entry.value.keys.toSet(), {'kk', 'en'}, reason: entry.key);
      for (final value in entry.value.values) {
        expect(value, isNotEmpty);
        expect(
          RegExp(r'\{\d+\}').allMatches(value).map((m) => m[0]).toSet(),
          RegExp(r'\{\d+\}').allMatches(entry.key).map((m) => m[0]).toSet(),
        );
      }
    }
    expect(translate('en', 'Получено: {0}', ['15000 ₸']), 'Received: 15000 ₸');
  });
  test('Selection survives a new controller', () async {
    final store = MemoryLanguage();
    final first = LanguageController(store, 'ru');
    await first.select('kk');
    expect(first.state, 'kk');
    first.dispose();
    final second = LanguageController(store, await store.read() ?? 'ru');
    expect(second.state, 'kk');
    second.dispose();
  });
  testWidgets('Language can be chosen on the login screen', (t) async {
    final store = MemoryLanguage();
    final c = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(
          ApiClient(MemoryTokens(), adapter: JsonAdapter(FixtureServer().call)),
        ),
        languageStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(container: c, child: const FlowzaApp()),
    );
    await t.pumpAndSettle();
    expect(find.text('Вход в CRM'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('English').last);
    await t.pumpAndSettle();
    expect(store.value, 'en');
    expect(find.text('Sign in to CRM'), findsOneWidget);
    expect(find.text('Phone or email'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final language in ['ru', 'kk', 'en']) {
    testWidgets('Mobile screens in $language keep client data', (t) async {
      t.view.physicalSize = const Size(390, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final tokens = MemoryTokens();
      await tokens.save('a', 'r');
      final c = ProviderContainer(
        overrides: [
          apiProvider.overrideWithValue(
            ApiClient(tokens, adapter: JsonAdapter(FixtureServer().call)),
          ),
          languageStoreProvider.overrideWithValue(MemoryLanguage()),
          initialLanguageProvider.overrideWithValue(language),
        ],
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const FlowzaApp()),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: "dashboard");
      for (final route in {
        '/orders': 'Заказы',
        '/clients': 'Клиенты',
        '/profile': 'Профиль',
        '/schedule': 'Календарь',
        '/notifications': 'Уведомления',
      }.entries) {
        c.read(routerProvider).go(route.key);
        await t.pumpAndSettle();
        expect(find.text(translate(language, route.value)), findsWidgets);
        expect(t.takeException(), isNull, reason: "route: ${route.key}");
      }
      c.read(routerProvider).go('/profile');
      await t.pumpAndSettle();
      expect(find.text('Арман'), findsOneWidget);
      expect(find.text('+77000000000'), findsOneWidget);
      expect(find.text(translate(language, 'Рабочий график')), findsOneWidget);
      final next = language == 'en' ? 'kk' : 'en';
      await c.read(languageProvider.notifier).select(next);
      await t.pumpAndSettle();
      expect(find.text(translate(next, 'Рабочий график')), findsOneWidget);
      expect(
        c.read(routerProvider).routeInformationProvider.value.uri.path,
        '/profile',
      );
      expect(find.text('Арман'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
