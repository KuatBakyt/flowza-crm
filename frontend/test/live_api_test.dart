import 'package:flutter_test/flutter_test.dart';
import 'package:flowza/core/api.dart';
import 'package:flowza/core/models.dart';

import 'helpers.dart';

const live = String.fromEnvironment('LIVE_API_URL');
void main() {
  test('Django: login create confirm calendar complete payment transfer refresh logout', () async {
    final tokens = MemoryTokens();
    final client = ApiClient(tokens, baseUrl: live);
    Future<UserDto> login(ApiClient c, String phone) async {
      final j = (await c.public.post<Json>(
        'auth/login/',
        data: {'phone': phone, 'password': 'integration-test-password'},
      )).data!;
      await c.tokens.save(j['access'] as String, j['refresh'] as String);
      return UserDto.fromJson(Json.from(await c.request('me/') as Map));
    }

    final user = await login(client, '+77000000000');
    expect(user.profile, isNotNull);
    final skills = await client.all('specializations/', (j) => j);
    final skill = skills.first['id'];
    final customer = await client.request(
      'clients/',
      method: 'POST',
      data: {
        'name': 'Smoke client',
        'phone': '+77012345678',
        'source': 'MANUAL',
        'notes': '',
      },
    );
    final start = DateTime.now().toUtc().add(const Duration(days: 2)),
        end = start.add(const Duration(hours: 2));
    final order = await client.request(
      'orders/',
      method: 'POST',
      data: {
        'client': customer['id'],
        'specialization': skill,
        'title': 'Smoke order',
        'description': 'API integration',
        'address': 'Алматы',
        'district': 'Бостандыкский',
        'start_at': start.toIso8601String(),
        'end_at': end.toIso8601String(),
        'estimated_price': '45000',
        'source': 'MANUAL',
      },
    );
    final id = order['id'];
    expect(
      (await client.request(
        'orders/$id/confirm/',
        method: 'POST',
        data: {},
      ))['status'],
      'CONFIRMED',
    );
    final blocks = await client.all(
      'schedule/',
      BlockDto.fromJson,
      query: {
        'from': start.subtract(const Duration(hours: 1)).toIso8601String(),
        'to': end.add(const Duration(hours: 1)).toIso8601String(),
      },
    );
    expect(blocks.any((b) => b.order == id), true);
    expect(
      (await client.request(
        'orders/$id/complete/',
        method: 'POST',
        data: {},
      ))['status'],
      'COMPLETED',
    );
    await client.request(
      'orders/$id/payments/', method: 'POST',
      data: {'amount': '10000', 'type': 'PREPAYMENT', 'status': 'PAID'},
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await client.request(
        'orders/$id/mark-paid/', method: 'POST',
        data: {'final_price': '45000'},
      );
    }
    final payments = await client.all('orders/$id/payments/', (j) => j);
    expect(payments.length, 2);
    final paidOrder = OrderDto.fromJson(Json.from(await client.request('orders/$id/') as Map));
    expect(paidOrder.paidAmount, '45000.00');
    expect(paidOrder.outstandingAmount, '0.00');
    expect((await client.request('dashboard/summary/'))['revenue'], '45000.00');
    final later = start.add(const Duration(days: 1));
    final other = await client.request(
      'orders/',
      method: 'POST',
      data: {
        'client': customer['id'],
        'specialization': skill,
        'title': 'Transfer smoke',
        'description': '',
        'address': 'Алматы',
        'district': 'Бостандыкский',
        'start_at': later.toIso8601String(),
        'end_at': later.add(const Duration(hours: 1)).toIso8601String(),
        'source': 'MANUAL',
      },
    );
    final offer = await client.request(
      'orders/${other['id']}/transfers/',
      method: 'POST',
      data: {'reason': 'Smoke auto selection'},
    );
    expect(offer['status'], 'OFFERED');
    expect(offer['to_master'], isNot(user.profile!.id));
    var accepted = false;
    for (final phone in ['+77000000001', '+77000000002']) {
      final recipient = ApiClient(MemoryTokens(), baseUrl: live);
      final u = await login(recipient, phone);
      if (u.profile!.id == offer['to_master']) {
        expect(
          (await recipient.request(
            'transfers/${offer['id']}/accept/',
            method: 'POST',
            data: {},
          ))['status'],
          'ACCEPTED',
        );
        accepted = true;
        break;
      }
    }
    expect(accepted, true);
    final oldRefresh = tokens.r;
    await tokens.save('expired-access', oldRefresh!);
    await client.request('me/');
    expect(tokens.r, isNot(oldRefresh));
    await client.request(
      'auth/logout/',
      method: 'POST',
      data: {'refresh': tokens.r},
    );
    await tokens.clear();
    await expectLater(client.request('me/'), throwsA(isA<Exception>()));
    client.dio.close();
  }, skip: live.isEmpty);
}
