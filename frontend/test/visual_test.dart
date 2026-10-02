import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowza/main.dart';
import 'package:flowza/core/api.dart';
import 'package:flowza/core/router.dart';
import 'package:flowza/features/schedule/presentation/schedule.dart';

import 'helpers.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_UI');
  setUpAll(() async {
    if (!capture) return;
    final sdk = Platform.environment['FLUTTER_ROOT']!;
    final loader = FontLoader('Roboto');
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          await File(
            '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes(),
        ),
      ),
    );
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      Future.value(
        ByteData.sublistView(
          await File(
            '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes(),
        ),
      ),
    );
    await icons.load();
    final fallback = FontLoader('Noto Sans');
    fallback.addFont(
      Future.value(
        ByteData.sublistView(
          await File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
              .readAsBytes(),
        ),
      ),
    );
    await fallback.load();
  });
  for (final entry in [
    ('phone-dashboard', '/', const Size(390, 844)),
    ('phone-orders', '/orders', const Size(390, 844)),
    ('phone-order-detail', '/orders/o1', const Size(390, 844)),
    ('phone-calendar', '/schedule', const Size(390, 844)),
    ('phone-profile', '/profile', const Size(390, 844)),
    ('desktop-dashboard', '/', const Size(1440, 1000)),
  ]) {
    testWidgets('Review ${entry.$1}', (t) async {
      if (!capture) return;
      t.view.physicalSize = entry.$3;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final tokens = MemoryTokens();
      await tokens.save('a', 'r');
      final server = FixtureServer();
      final container = ProviderContainer(
        overrides: [
          apiProvider.overrideWithValue(
            ApiClient(tokens, adapter: JsonAdapter(server.call)),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(calendarDate.notifier).state = DateTime(2026, 11, 3);
      final key = GlobalKey();
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: key, child: const FlowzaApp()),
        ),
      );
      await t.pumpAndSettle();
      container.read(routerProvider).go(entry.$2);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('../docs/screenshots/${entry.$1}.png'),
      );
    }, skip: !capture);
  }
}
