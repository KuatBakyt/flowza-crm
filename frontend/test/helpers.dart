import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flowza/core/api.dart';
import 'package:flowza/core/models.dart';

class MemoryTokens implements TokenStore {
  String? a, r;
  @override
  Future<String?> access() async => a;
  @override
  Future<String?> refresh() async => r;
  @override
  Future<void> save(String access, String refresh) async {
    a = access;
    r = refresh;
  }

  @override
  Future<void> clear() async {
    a = null;
    r = null;
  }
}

class JsonAdapter implements HttpClientAdapter {
  final Future<(int, Object)> Function(RequestOptions) handler;
  JsonAdapter(this.handler);
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final (status, json) = await handler(options);
    return ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

final userJson = <String, dynamic>{
  'id': 'u1',
  'phone': '+77000000000',
  'email': null,
  'role': 'MASTER',
  'master_profile': {
    'id': 'm1',
    'full_name': 'Арман',
    'city': 'Алматы',
    'districts': ['Алмалинский'],
    'is_available': true,
    'internal_rating': '4.80',
    'completed_orders_count': 12,
    'skills': [
      {
        'id': 's1',
        'specialization': 'sp1',
        'experience_years': 3,
        'is_active': true,
      },
    ],
  },
};
final clientJson = <String, dynamic>{
  'id': 'c1',
  'name': 'Ерлан',
  'phone': '+77771234567',
  'source': 'MANUAL',
  'notes': 'Постоянный клиент',
};
Json orderJson([String status = 'NEW']) => {
  'id': 'o1',
  'client': 'c1',
  'master': 'm1',
  'specialization': 'sp1',
  'title': 'Поклейка обоев',
  'description': 'Снять старые обои и поклеить новые. Комната 25 м².',
  'address': 'Алматы, ул. Абая, 15',
  'district': 'Алмалинский район',
  'start_at': DateTime(2026, 11, 3, 9).toUtc().toIso8601String(),
  'end_at': DateTime(2026, 11, 3, 13).toUtc().toIso8601String(),
  'estimated_price': '45000.00',
  'final_price': null,
  'status': status,
  'source': 'MANUAL',
  'status_history': [
    {
      'to_status': 'NEW',
      'from_status': '',
      'note': 'Заявка создана',
      'created_at': '2026-10-02T09:00:00Z',
    },
  ],
};

class FixtureServer {
  String status = 'NEW';
  final List<String> actions = [];
  int ordersStatus = 200;
  bool empty = false;
  final List<Json> requests = [];
  Future<(int, Object)> call(RequestOptions o) async {
    final path = Uri.parse(o.path).path;
    requests.add({
      'path': path,
      'method': o.method,
      'data': o.data,
      'query': o.queryParameters,
    });
    if (path.endsWith('auth/login/')) {
      return (200, {'access': 'access', 'refresh': 'refresh'});
    }
    if (path.endsWith('auth/logout/')) return (204, {});
    if (path.endsWith('me/')) return (200, userJson);
    if (path.endsWith('dashboard/summary/')) {
      return (
        200,
        {
          'new': 2,
          'active': 3,
          'completed': 5,
          'cancelled': 1,
          'transferred': 1,
          'revenue': '85000.00',
        },
      );
    }
    if (path.contains('specializations/')) {
      return page([
        {'id': 'sp1', 'name': 'Отделочные работы', 'is_active': true},
      ]);
    }
    if (path.contains('masters/')) {
      return page([userJson['master_profile'] as Json]);
    }
    if (path.endsWith('clients/c1/orders/')) return page([orderJson(status)]);
    if (path.endsWith('clients/c1/')) return (200, clientJson);
    if (path.endsWith('clients/')) return page([clientJson]);
    if (path.endsWith('orders/o1/confirm/')) {
      actions.add('confirm');
      status = 'CONFIRMED';
      return (200, orderJson(status));
    }
    if (path.endsWith('orders/o1/')) return (200, orderJson(status));
    if (path.endsWith('orders/')) {
      return ordersStatus == 200
          ? page(empty ? [] : [orderJson(status)])
          : (500, {'code': 'error', 'message': 'Ошибка загрузки'});
    }
    if (path.endsWith('schedule/')) {
      return page([
        {
          'id': 'b1',
          'master': 'm1',
          'order': 'o1',
          'type': 'ORDER',
          'note': 'Поклейка обоев',
          'start_at': DateTime(2026, 11, 3, 9).toUtc().toIso8601String(),
          'end_at': DateTime(2026, 11, 3, 13).toUtc().toIso8601String(),
        },
      ]);
    }
    if (path.contains('payments/') || path.contains('orders/o1/transfers/')) {
      return (200, []);
    }
    return page([]);
  }

  (int, Object) page(List<Object?> list) => (
    200,
    {'count': list.length, 'next': null, 'previous': null, 'results': list},
  );
}
