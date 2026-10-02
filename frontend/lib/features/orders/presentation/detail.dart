import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/appointment_check.dart';
import '../../../core/models.dart';
import '../../../core/ui.dart';
import '../../../core/catalogs.dart';

final paymentsProvider = FutureProvider.family<List<Json>, String>((ref, id) {
  ref.watch(revisionProvider);
  ref.watch(liveRevisionProvider);
  return ref.read(apiProvider).all('orders/$id/payments/', (j) => j);
});
final historyTransfersProvider =
    FutureProvider.family<List<TransferDto>, String>((ref, id) {
      ref.watch(revisionProvider);
      ref.watch(liveRevisionProvider);
      return ref
          .read(apiProvider)
          .all('orders/$id/transfers/', TransferDto.fromJson);
    });

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const OrderDetailScreen(this.id, {super.key});
  @override
  ConsumerState<OrderDetailScreen> createState() => _Detail();
}

class _Detail extends ConsumerState<OrderDetailScreen> {
  bool busy = false;
  Future<void> action(String action, [Json? body]) async {
    setState(() => busy = true);
    await mutate(context, ref, () async {
      await ref
          .read(apiProvider)
          .request(
            'orders/${widget.id}/$action/',
            method: 'POST',
            data: body ?? {},
          );
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> dialog(String mode, OrderDto o) async {
    final body = await showDialog<Json>(
      context: context,
      builder: (c) => OrderActionDialog(mode, o),
    );
    if (body == null || !mounted) return;
    if (mode == 'reschedule' && o.master != null) {
      try {
        if (!await checkAppointment(
          context,
          ref.read(apiProvider),
          o.master!,
          DateTime.parse(body['new_start_at'] as String),
          DateTime.parse(body['new_end_at'] as String),
          excludeOrder: o.id,
        )) {
          return;
        }
      } catch (e) {
        if (mounted) showError(context, e);
        return;
      }
    }
    await action(mode, body);
  }

  @override
  Widget build(BuildContext context) => PageBody(
    'Карточка заказа',
    children: [
      AsyncBox(
        value: ref.watch(orderProvider(widget.id)),
        retry: () => ref.invalidate(orderProvider(widget.id)),
        data: (o) {
          final clients = ref.watch(clientsCatalog).valueOrNull ?? [];
          final c = clients.where((c) => c.id == o.client).firstOrNull;
          final editable = ['NEW', 'PENDING', 'CONFIRMED'].contains(o.status),
              live = [
                'NEW',
                'PENDING',
                'CONFIRMED',
                'IN_PROGRESS',
                'TRANSFERRED',
              ].contains(o.status);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusBadge(o.status),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Avatar(c?.label ?? 'Клиент'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            c?.label ?? 'Клиент',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (c != null)
                          IconButton(
                            onPressed: () => context.push('/clients/${c.id}'),
                            icon: const Icon(Icons.person_outline, color: blue),
                          ),
                      ],
                    ),
                    if (c != null) Info(Icons.phone_outlined, c.phone),
                    const Divider(height: 32),
                    Text(
                      o.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Info(
                      Icons.place_outlined,
                      '${o.address}${o.district.isEmpty ? '' : ', ${o.district}'}',
                    ),
                    Info(Icons.calendar_today_outlined, when(o.startAt)),
                    Info(
                      Icons.schedule,
                      '${clock(o.startAt)} – ${clock(o.endAt)}',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Описание',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(o.description.isEmpty ? 'Не указано' : o.description),
                    const SizedBox(height: 20),
                    const Text(
                      'Стоимость',
                      style: TextStyle(color: Color(0xFF78869C)),
                    ),
                    Text(
                      money(o.finalPrice ?? o.estimatedPrice),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text("Получено: ${money(o.paidAmount)}"),
                    if (o.outstandingAmount != null)
                      Text("Осталось: ${money(o.outstandingAmount)}"),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (['NEW', 'PENDING', 'TRANSFERRED'].contains(o.status))
                FilledButton(
                  onPressed: busy ? null : () => action('confirm'),
                  child: const Text('Подтвердить заказ'),
                ),
              if (o.status == 'CONFIRMED')
                FilledButton(
                  onPressed: busy ? null : () => action('start'),
                  child: const Text('Начать работу'),
                ),
              if (['CONFIRMED', 'IN_PROGRESS'].contains(o.status))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton(
                    onPressed: busy ? null : () => action('complete'),
                    child: const Text('Завершить работу'),
                  ),
                ),
              if (o.status == 'COMPLETED')
                FilledButton(
                  onPressed: busy ? null : () => dialog('mark-paid', o),
                  child: const Text('Отметить оплаченным'),
                ),
              if (editable) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => dialog('reschedule', o),
                  icon: const Icon(Icons.event_repeat),
                  label: const Text('Перенести'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => context.push('/orders/${o.id}/edit'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Редактировать'),
                ),
              ],
              if (live) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy || !editable
                      ? null
                      : () => context.push('/orders/${o.id}/transfer'),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Передать в систему'),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: busy ? null : () => dialog('cancel', o),
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  label: const Text(
                    'Отменить заказ',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Text('Платежи', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : () => dialog('payments', o),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Зафиксировать платёж'),
              ),
              const SizedBox(height: 12),
              AsyncBox(
                value: ref.watch(paymentsProvider(o.id)),
                retry: () => ref.invalidate(paymentsProvider(o.id)),
                data: (p) => p.isEmpty
                    ? const Empty(
                        'Платежей пока нет',
                        body: 'Отметка «Оплачен» и учёт платежей — отдельные действия.',
                      )
                    : Surface(
                        child: Column(
                          children: [
                            for (final j in p)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.payments_outlined,
                                  color: blue,
                                ),
                                title: Text(money(j['amount'])),
                                subtitle: Text('${j['type']} · ${j['status']}'),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 28),
              Text(
                'История заказа',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Surface(
                child: Column(
                  children: [
                    for (final j in o.statusHistory)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.radio_button_checked,
                          color: blue,
                          size: 18,
                        ),
                        title: Text(
                          statuses[j['to_status']] ?? j['to_status'].toString(),
                        ),
                        subtitle: Text(
                          '${when(DateTime.parse(j['created_at'] as String))}${(j['note'] ?? '').toString().isEmpty ? '' : '\n${j['note']}'}',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'История передач',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              AsyncBox(
                value: ref.watch(historyTransfersProvider(o.id)),
                retry: () => ref.invalidate(historyTransfersProvider(o.id)),
                data: (list) => list.isEmpty
                    ? const Empty('Передач ещё не было')
                    : Surface(
                        child: Column(
                          children: [
                            for (final t in list)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(statuses[t.status] ?? t.status),
                                subtitle: Text(
                                  '${when(t.offeredAt)}\n${t.reason}',
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    ],
  );
}

class OrderActionDialog extends StatefulWidget {
  final String mode;
  final OrderDto order;
  const OrderActionDialog(this.mode, this.order, {super.key});
  @override
  State<OrderActionDialog> createState() => _ActionDialog();
}

class _ActionDialog extends State<OrderActionDialog> {
  final key = GlobalKey<FormState>(), text = TextEditingController();
  late DateTime start, end;
  String by = 'CLIENT', type = 'FULL', paymentStatus = 'PAID';
  @override
  void initState() {
    super.initState();
    start = widget.order.startAt.toLocal();
    end = widget.order.endAt.toLocal();
    if (widget.mode == 'mark-paid') {
      text.text = widget.order.estimatedPrice ?? '';
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    return AlertDialog(
      title: Text(
        {
          'cancel': 'Отменить заказ',
          'reschedule': 'Перенести заказ',
          'mark-paid': 'Отметить оплаченным',
          'payments': 'Новый платёж',
        }[mode]!,
      ),
      content: SingleChildScrollView(
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mode == 'reschedule') ...[
                OutlinedButton(
                  onPressed: () async {
                    final d = await pickDateTime(context, start);
                    if (d != null) setState(() => start = d);
                  },
                  child: Text('Начало: ${when(start)}'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final d = await pickDateTime(context, end);
                    if (d != null) setState(() => end = d);
                  },
                  child: Text('Конец: ${when(end)}'),
                ),
              ] else ...[
                if (mode == 'cancel')
                  DropdownButtonFormField<String>(
                    initialValue: by,
                    items: const [
                      DropdownMenuItem(
                        value: 'CLIENT',
                        child: Text('Отмена клиентом'),
                      ),
                      DropdownMenuItem(
                        value: 'MASTER',
                        child: Text('Отмена мастером'),
                      ),
                    ],
                    onChanged: (v) => by = v!,
                  ),
                TextFormField(
                  controller: text,
                  decoration: InputDecoration(
                    labelText: mode == 'cancel'
                        ? 'Причина отмены *'
                        : 'Сумма, ₸ *',
                  ),
                  keyboardType: mode == 'cancel'
                      ? TextInputType.text
                      : const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Обязательное поле';
                    }
                    if (mode == 'cancel') return null;
                    final n = num.tryParse(v.replaceAll(',', '.'));
                    return n == null || n < (mode == 'payments' ? 0.01 : 0)
                        ? 'Некорректная сумма'
                        : null;
                  },
                ),
                if (mode == 'payments') ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: const [
                      DropdownMenuItem(
                        value: 'FULL',
                        child: Text('Полная оплата'),
                      ),
                      DropdownMenuItem(
                        value: 'PREPAYMENT',
                        child: Text('Предоплата'),
                      ),
                      DropdownMenuItem(value: 'REFUND', child: Text('Возврат')),
                    ],
                    onChanged: (v) => setState(() {
                      type = v!;
                      paymentStatus = type == 'REFUND' ? 'REFUNDED' : 'PAID';
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(type),
                    initialValue: paymentStatus,
                    items: [
                      for (final s
                          in type == 'REFUND'
                              ? ['REFUNDED']
                              : ['PAID', 'PENDING'])
                        DropdownMenuItem(
                          value: s,
                          child: Text(
                            {
                              'PAID': 'Оплачен',
                              'PENDING': 'Ожидается',
                              'REFUNDED': 'Возвращён',
                            }[s]!,
                          ),
                        ),
                    ],
                    onChanged: (v) => paymentStatus = v!,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Назад'),
        ),
        FilledButton(
          onPressed: () {
            if (!key.currentState!.validate()) return;
            if (mode == 'reschedule' && !start.isBefore(end)) {
              showError(
                context,
                Exception('Начало должно быть раньше окончания'),
              );
              return;
            }
            Navigator.pop(context, switch (mode) {
              'cancel' => {'reason': text.text.trim(), 'cancelled_by': by},
              'reschedule' => {
                'new_start_at': iso(start),
                'new_end_at': iso(end),
              },
              'mark-paid' => {'final_price': text.text.replaceAll(',', '.')},
              _ => {
                'amount': text.text.replaceAll(',', '.'),
                'type': type,
                'status': paymentStatus,
              },
            });
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
