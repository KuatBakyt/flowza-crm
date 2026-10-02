import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowza/core/api.dart';
import 'package:flowza/core/failure.dart';
import 'package:dio/dio.dart';

import 'helpers.dart';

void main() {
  test('Concurrent 401 refreshes once and saves rotated pair', () async {
    final tokens = MemoryTokens();
    await tokens.save('old', 'refresh');
    int refreshes = 0;
    final api = ApiClient(
      tokens,
      baseUrl: 'http://test/api/',
      adapter: JsonAdapter((o) async {
        if (o.path.endsWith('refresh/')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return (200, {'access': 'new', 'refresh': 'rotated'});
        }
        return o.headers['Authorization'] == 'Bearer new'
            ? (200, {'ok': true})
            : (401, {'detail': 'expired'});
      }),
    );
    final results = await Future.wait([
      api.request('orders/'),
      api.request('clients/'),
    ]);
    expect(results.length, 2);
    expect(refreshes, 1);
    expect(tokens.a, 'new');
    expect(tokens.r, 'rotated');
  });
  test('Failed refresh clears tokens and signs out', () async {
    final tokens = MemoryTokens();
    await tokens.save('old', 'r');
    var loggedOut = false;
    final api = ApiClient(
      tokens,
      adapter: JsonAdapter((o) async => (401, {'message': 'expired'})),
    );
    api.onUnauthorized = () => loggedOut = true;
    await expectLater(api.request('orders/'), throwsA(isA<AppFailure>()));
    expect(tokens.a, isNull);
    expect(loggedOut, true);
  });
  test('A repeated 401 is retried only once', () async {
    final tokens = MemoryTokens();
    await tokens.save('old', 'r');
    var refreshes = 0;
    final api = ApiClient(
      tokens,
      adapter: JsonAdapter((o) async {
        if (o.path.endsWith('refresh/')) {
          refreshes++;
          return (200, {'access': 'new', 'refresh': 'next'});
        }
        return (401, {'detail': 'denied'});
      }),
    );
    await expectLater(api.request('orders/'), throwsA(isA<AppFailure>()));
    expect(refreshes, 1);
    expect(tokens.a, isNull);
  });
  test('Logout during refresh cannot restore session', () async {
    final tokens = MemoryTokens();
    await tokens.save('old', 'r');
    final waiting = Completer<void>(), release = Completer<void>();
    final api = ApiClient(
      tokens,
      adapter: JsonAdapter((o) async {
        if (o.path.endsWith('refresh/')) {
          waiting.complete();
          await release.future;
          return (200, {'access': 'new', 'refresh': 'next'});
        }
        return (401, {});
      }),
    );
    final request = expectLater(
      api.request('orders/'),
      throwsA(isA<AppFailure>()),
    );
    await waiting.future;
    await tokens.clear();
    release.complete();
    await request;
    expect(tokens.a, isNull);
  });
  test('Django error keeps code message and fields', () {
    final result = ApiClient.failure(
      DioException(
        requestOptions: RequestOptions(path: 'orders/'),
        response: Response(
          requestOptions: RequestOptions(path: 'orders/'),
          statusCode: 409,
          data: {
            'code': 'schedule_conflict',
            'message': 'Время занято',
            'fields': {
              'start_at': ['Конфликт'],
            },
          },
        ),
      ),
    );
    expect(result.code, 'schedule_conflict');
    expect(result.fields['start_at'], ['Конфликт']);
  });
}
