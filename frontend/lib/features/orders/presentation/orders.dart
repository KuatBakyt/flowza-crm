import '../../../core/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models.dart';
import '../../../core/ui.dart';
import '../../../core/catalogs.dart';
import 'providers.dart';

class OrderCard extends ConsumerWidget {
  final OrderDto order;
  const OrderCard(this.order, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(clientsCatalog).valueOrNull ?? [];
    final client = clients.where((c) => c.id == order.client).firstOrNull;
    return Surface(
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusBadge(order.status),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Color(0xFF95A2B6)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              client?.label ?? tr(context, "Клиент"),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              order.title,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Info(
              Icons.schedule,
              '${when(order.startAt)} – ${clock(order.endAt)}',
            ),
            Info(
              Icons.place_outlined,
              order.district.isEmpty ? order.address : order.district,
            ),
            const SizedBox(height: 8),
            Text(
              money(order.finalPrice ?? order.estimatedPrice),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _Orders();
}

class _Orders extends ConsumerState<OrdersScreen> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void filter(String key, Object? value) {
    final current = {...ref.read(ordersFilter)};
    if (value == null || value == '') {
      current.remove(key);
    } else {
      current[key] = value;
    }
    ref.read(ordersFilter.notifier).state = current;
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(ordersFilter);
    return PageBody(
      tr(context, "Заказы"),
      action: IconButton(
        onPressed: () => context.push('/orders/new'),
        icon: const Icon(Icons.add_circle_outline, color: blue),
      ),
      children: [
        TextField(
          controller: search,
          decoration: InputDecoration(
            hintText: tr(context, "Клиент, телефон или услуга"),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              onPressed: () => filter('search', search.text.trim()),
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
          onSubmitted: (s) => filter('search', s.trim()),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry
                  in {'': tr(context, "Все"), ...statuses}.entries.where(
                    (e) =>
                        e.key == '' ||
                        ![
                          'OFFERED',
                          'ACCEPTED',
                          'DECLINED',
                          'EXPIRED',
                        ].contains(e.key),
                  ))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tr(context, entry.value)),
                    selected: (q['status'] ?? '') == entry.key,
                    onSelected: (_) => filter('status', entry.key),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (d != null) {
                    filter('date_from', iso(d));
                    filter(
                      'date_to',
                      iso(
                        d
                            .add(const Duration(days: 1))
                            .subtract(const Duration(milliseconds: 1)),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  q.containsKey('date_from')
                      ? tr(context, "Дата выбрана")
                      : tr(context, "Фильтр по дате"),
                ),
              ),
            ),
            if (q.containsKey('date_from'))
              IconButton(
                onPressed: () {
                  filter('date_from', null);
                  filter('date_to', null);
                },
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        AsyncBox(
          value: ref.watch(ordersProvider),
          retry: () => ref.invalidate(ordersProvider),
          data: (p) => p.items.isEmpty
              ? Empty(
                  tr(context, "Заказов пока нет"),
                  body: tr(context, "Добавьте заказ или измените фильтры."),
                )
              : Column(
                  children: [
                    for (final o in p.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: OrderCard(o),
                      ),
                    if (p.hasNext)
                      MoreButton(ref.read(ordersProvider.notifier).more),
                  ],
                ),
        ),
      ],
    );
  }
}
