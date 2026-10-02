import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flowza/core/api.dart';
import 'package:flowza/features/auth/presentation/auth.dart';
import 'package:flowza/features/orders/presentation/providers.dart';
import 'package:flowza/features/transfers/presentation/providers.dart';

import 'helpers.dart';

void main() {
  test('Auth restores, logs in and signs out', () async {
    final tokens = MemoryTokens(), server = FixtureServer();
    final api = ApiClient(tokens, adapter: JsonAdapter(server.call));
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    expect(await container.read(authProvider.future), isNull);
    await container
        .read(authProvider.notifier)
        .login('+77000000000', 'password');
    expect(container.read(authProvider).value?.profile?.fullName, 'Арман');
    await container.read(authProvider.notifier).logout();
    expect(container.read(authProvider).value, isNull);
    expect(tokens.a, isNull);
  });
  test('Orders use filters and load next page', () async {
    final queries = <Map<String, dynamic>>[];
    final api = ApiClient(
      MemoryTokens(),
      adapter: JsonAdapter((o) async {
        queries.add(o.queryParameters);
        final page = o.queryParameters['page'] as int;
        return (
          200,
          {
            'count': 2,
            'next': page == 1 ? 'http://test?page=2' : null,
            'results': [orderJson()..['id'] = 'o$page'],
          },
        );
      }),
    );
    final container = ProviderContainer(
      overrides: [apiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container.read(ordersFilter.notifier).state = {'status': 'NEW'};
    expect((await container.read(ordersProvider.future)).items.length, 1);
    await container.read(ordersProvider.notifier).more();
    expect(container.read(ordersProvider).value!.items.length, 2);
    expect(queries.last['page'], 2);
    expect(queries.last['status'], 'NEW');
  });
  test('Incoming proposals use the dedicated endpoint', () async {
    final server = FixtureServer();
    final container = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(
          ApiClient(MemoryTokens(), adapter: JsonAdapter(server.call)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(transfersProvider.future);
    expect(server.requests.last['path'], 'transfers/incoming/');
    container.read(transfersFilter.notifier).state = {'history': true};
    await container.read(transfersProvider.future);
    expect(server.requests.last['path'], 'transfers/');
  });
  test(
    'Background refresh keeps loaded pages and updates external orders',
    () async {
      var title = 'Before';
      final api = ApiClient(
        MemoryTokens(),
        adapter: JsonAdapter((o) async {
          final page = o.queryParameters['page'] as int;
          return (
            200,
            {
              'count': 2,
              'next': page == 1 ? 'next' : null,
              'results': [
                orderJson()
                  ..['id'] = 'o$page'
                  ..['title'] = title,
              ],
            },
          );
        }),
      );
      final container = ProviderContainer(
        overrides: [apiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(ordersProvider.future);
      await container.read(ordersProvider.notifier).more();
      title = 'From bot';
      await container.read(ordersProvider.notifier).refreshVisible();
      final result = container.read(ordersProvider).value!;
      expect(result.page, 2);
      expect(result.items.length, 2);
      expect(result.items.first.title, 'From bot');
    },
  );
}
