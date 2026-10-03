import '../../../core/l10n.dart';

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
  ref.watch(liveRevisionProvider);
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
  ref.watch(liveRevisionProvider);
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
      tr(context, "Привет, {0}!", [
        u?.name.split(' ').first ?? tr(context, 'мастер'),
      ]),
      action: IconButton(
        onPressed: () => context.push('/notifications'),
        icon: const Icon(Icons.notifications_outlined),
      ),
      children: [
        Text(
          tr(context, "Ваш рабочий день под контролем"),
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
                    tr(context, "Новые"),
                    s.newOrders.toString(),
                    const Color(0xFFFFEEDB),
                  ),
                  Metric(
                    tr(context, "В работе"),
                    s.active.toString(),
                    const Color(0xFFDCF5EB),
                  ),
                  Metric(
                    tr(context, "Доход за неделю"),
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
          label: Text(tr(context, "Добавить заказ")),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                tr(context, "Сегодня"),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/orders'),
              child: Text(tr(context, "Все заказы")),
            ),
          ],
        ),
        AsyncBox(
          value: ref.watch(todayProvider),
          retry: () => ref.invalidate(todayProvider),
          data: (orders) => orders.isEmpty
              ? Empty(
                  tr(context, "На сегодня заказов нет"),
                  body: tr(
                    context,
                    "Свободное время можно отметить в календаре.",
                  ),
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
                title: Text(tr(context, "Входящие предложения")),
                subtitle: Text(tr(context, "Заказы, подобранные системой")),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/transfers'),
              ),
              ListTile(
                leading: const Icon(Icons.people_outline, color: blue),
                title: Text(tr(context, "Клиенты")),
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
    tr(context, "Статистика"),
    children: [
      DropdownButtonFormField<String>(
        initialValue: ref.watch(summaryPeriod),
        decoration: InputDecoration(labelText: tr(context, "Период")),
        items: [
          DropdownMenuItem(value: 'day', child: Text(tr(context, "За день"))),
          DropdownMenuItem(
            value: 'week',
            child: Text(tr(context, "За неделю")),
          ),
          DropdownMenuItem(
            value: 'month',
            child: Text(tr(context, "За 30 дней")),
          ),
        ],
        onChanged: (v) => ref.read(summaryPeriod.notifier).state = v!,
      ),
      AsyncBox(
        value: ref.watch(summaryProvider),
        retry: () => ref.invalidate(summaryProvider),
        data: (s) => Column(
          children: [
            Metric(
              tr(context, "Доход по платежам"),
              money(s.revenue),
              const Color(0xFFDCF5EB),
            ),
            const SizedBox(height: 16),
            Surface(
              child: Column(
                children: [
                  Info(
                    Icons.check_circle_outline,
                    tr(context, "Выполнено: {0}", [s.completed]),
                  ),
                  Info(
                    Icons.work_outline,
                    tr(context, "Активных заказов: {0}", [s.active]),
                  ),
                  Info(
                    Icons.fiber_new_outlined,
                    tr(context, "Новых: {0}", [s.newOrders]),
                  ),
                  Info(
                    Icons.cancel_outlined,
                    tr(context, "Отменено: {0}", [s.cancelled]),
                  ),
                  Info(
                    Icons.swap_horiz,
                    tr(context, "Передано: {0}", [s.transferred]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
