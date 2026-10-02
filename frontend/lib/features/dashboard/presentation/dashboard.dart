import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';
import '../../../core/ui.dart';
import '../../../core/catalogs.dart';
import '../../auth/presentation/auth.dart';
import '../../orders/presentation/orders.dart';

final todayProvider = FutureProvider<List<OrderDto>>((ref) {
  ref.watch(revisionProvider);
  final n = DateTime.now(), d = DateTime(n.year, n.month, n.day);
  return ref
      .read(apiProvider)
      .all(
        'orders/',
        OrderDto.fromJson,
        query: {
          'date_from': iso(d),
          'date_to': iso(
            d
                .add(const Duration(days: 1))
                .subtract(const Duration(milliseconds: 1)),
          ),
          'ordering': 'start_at',
        },
      );
});

final dashboardSummaryProvider = FutureProvider<SummaryDto>((ref) async {
  ref.watch(revisionProvider);
  return SummaryDto.fromJson(
    Json.from(
      await ref
              .read(apiProvider)
              .request('dashboard/summary/', query: {'period': 'week'})
          as Map,
    ),
  );
});

class Metric extends StatelessWidget {
  final String label, value;
  final Color color;
  const Metric(this.label, this.value, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: ink)),
      ],
    ),
  );
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(authProvider).valueOrNull;
    return PageBody(
      'Привет, ${u?.name.split(' ').first ?? 'мастер'}!',
      action: IconButton(
        onPressed: () => context.push('/notifications'),
        icon: const Icon(Icons.notifications_outlined),
      ),
      children: [
        const Text(
          'Ваш рабочий день под контролем',
          style: TextStyle(color: Color(0xFF78869C)),
        ),
        AsyncBox(
          value: ref.watch(dashboardSummaryProvider),
          retry: () => ref.invalidate(dashboardSummaryProvider),
          data: (s) => LayoutBuilder(
            builder: (c, b) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final w in [
                  Metric(
                    'Новые',
                    s.newOrders.toString(),
                    const Color(0xFFFFEEDB),
                  ),
                  Metric(
                    'В работе',
                    s.active.toString(),
                    const Color(0xFFDCF5EB),
                  ),
                  Metric(
                    'Доход за неделю',
                    money(s.revenue),
                    const Color(0xFFE2EBFF),
                  ),
                ])
                  SizedBox(
                    width: b.maxWidth < 500
                        ? (b.maxWidth - 12) / 2
                        : (b.maxWidth - 24) / 3,
                    child: w,
                  ),
              ],
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () => context.push('/orders/new'),
          icon: const Icon(Icons.add),
          label: const Text('Добавить заказ'),
        ),
        Row(
          children: [
            Text('Сегодня', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton(
              onPressed: () => context.go('/orders'),
              child: const Text('Все заказы'),
            ),
          ],
        ),
        AsyncBox(
          value: ref.watch(todayProvider),
          retry: () => ref.invalidate(todayProvider),
          data: (orders) => orders.isEmpty
              ? const Empty(
                  'На сегодня заказов нет',
                  body: 'Свободное время можно отметить в календаре.',
                )
              : Column(
                  children: [
                    for (final o in orders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: OrderCard(o),
                      ),
                  ],
                ),
        ),
        Surface(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.swap_horiz, color: blue),
                title: const Text('Входящие предложения'),
                subtitle: const Text('Заказы, подобранные системой'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/transfers'),
              ),
              ListTile(
                leading: const Icon(Icons.people_outline, color: blue),
                title: const Text('Клиенты'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/clients'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    'Статистика',
    children: [
      DropdownButtonFormField<String>(
        initialValue: ref.watch(summaryPeriod),
        decoration: const InputDecoration(labelText: 'Период'),
        items: const [
          DropdownMenuItem(value: 'day', child: Text('За день')),
          DropdownMenuItem(value: 'week', child: Text('За неделю')),
          DropdownMenuItem(value: 'month', child: Text('За 30 дней')),
        ],
        onChanged: (v) => ref.read(summaryPeriod.notifier).state = v!,
      ),
      AsyncBox(
        value: ref.watch(summaryProvider),
        retry: () => ref.invalidate(summaryProvider),
        data: (s) => Column(
          children: [
            Metric(
              'Доход по платежам',
              money(s.revenue),
              const Color(0xFFDCF5EB),
            ),
            const SizedBox(height: 16),
            Surface(
              child: Column(
                children: [
                  Info(Icons.check_circle_outline, 'Выполнено: ${s.completed}'),
                  Info(Icons.work_outline, 'Активных заказов: ${s.active}'),
                  Info(Icons.fiber_new_outlined, 'Новых: ${s.newOrders}'),
                  Info(Icons.cancel_outlined, 'Отменено: ${s.cancelled}'),
                  Info(Icons.swap_horiz, 'Передано: ${s.transferred}'),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
