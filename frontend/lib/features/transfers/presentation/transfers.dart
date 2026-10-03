import '../../../core/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';
import '../../../core/ui.dart';
import '../../auth/presentation/auth.dart';
import 'providers.dart';

class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});
  @override
  ConsumerState<TransfersScreen> createState() => _Transfers();
}

class _Transfers extends ConsumerState<TransfersScreen> {
  bool get history => ref.read(transfersFilter)['history'] == true;
  String? busy;
  @override
  Widget build(BuildContext context) => PageBody(
    tr(context, "Предложения заказов"),
    children: [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(tr(context, "Входящие"))),
          ButtonSegment(value: true, label: Text(tr(context, "История"))),
        ],
        selected: {ref.watch(transfersFilter)['history'] == true},
        onSelectionChanged: (v) {
          ref.read(transfersFilter.notifier).state = v.first
              ? {'history': true}
              : {};
        },
      ),
      AsyncBox(
        value: ref.watch(transfersProvider),
        retry: () => ref.invalidate(transfersProvider),
        data: (p) => p.items.isEmpty
            ? Empty(
                history
                    ? tr(context, "Передач пока нет")
                    : tr(context, "Нет входящих предложений"),
                body: tr(
                  context,
                  "Система подбирает заказы по специализации и свободному времени.",
                ),
              )
            : Column(
                children: [
                  for (final t in p.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(t.status),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              t.orderDetails['title'] as String,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Info(
                              Icons.place_outlined,
                              '${t.orderDetails['address']} · ${t.orderDetails['district']}',
                            ),
                            Info(
                              Icons.schedule,
                              '${when(DateTime.parse(t.orderDetails['start_at'] as String))} – ${clock(DateTime.parse(t.orderDetails['end_at'] as String))}',
                            ),
                            Text(
                              money(t.orderDetails['estimated_price']),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (t.reason.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(t.reason),
                              ),
                            if (t.status == 'OFFERED' &&
                                (ref.watch(authProvider).valueOrNull?.admin ==
                                        true ||
                                    ref
                                            .watch(authProvider)
                                            .valueOrNull
                                            ?.profile
                                            ?.id ==
                                        t.toMaster)) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: busy != null
                                          ? null
                                          : () => respond(t, 'accept'),
                                      child: Text(tr(context, "Принять")),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: busy != null
                                          ? null
                                          : () => respond(t, 'decline'),
                                      child: Text(tr(context, "Не могу")),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (t.status == 'ACCEPTED' &&
                                (ref.watch(authProvider).valueOrNull?.admin ==
                                        true ||
                                    ref
                                            .watch(authProvider)
                                            .valueOrNull
                                            ?.profile
                                            ?.id ==
                                        t.toMaster))
                              TextButton(
                                onPressed: () =>
                                    context.push('/orders/${t.order}'),
                                child: Text(tr(context, "Открыть заказ")),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (p.hasNext)
                    MoreButton(ref.read(transfersProvider.notifier).more),
                ],
              ),
      ),
    ],
  );
  Future<void> respond(TransferDto t, String action) async {
    setState(() => busy = t.id);
    await mutate(
      context,
      ref,
      () async {
        await ref
            .read(apiProvider)
            .request('transfers/${t.id}/$action/', method: 'POST', data: {});
      },
      message: action == 'accept'
          ? tr(context, "Заказ принят, время забронировано")
          : tr(context, "Предложение отклонено"),
    );
    if (mounted) setState(() => busy = null);
  }
}

class OfferScreen extends ConsumerStatefulWidget {
  final String id;
  const OfferScreen(this.id, {super.key});
  @override
  ConsumerState<OfferScreen> createState() => _Offer();
}

class _Offer extends ConsumerState<OfferScreen> {
  String reason = 'Занят в это время';
  final comment = TextEditingController();
  bool busy = false, sent = false;
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageBody(
    tr(context, "Передача заказа"),
    children: [
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              sent ? Icons.check_circle_outline : Icons.person_search_outlined,
              color: blue,
              size: 64,
            ),
            const SizedBox(height: 20),
            Text(
              sent
                  ? tr(context, "Предложение отправлено")
                  : tr(context, "Не можете выполнить заказ?"),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              sent
                  ? tr(
                      context,
                      "Заказ будет передан после принятия новым мастером. Следите за статусом в истории передач.",
                    )
                  : tr(
                      context,
                      "Система автоматически подберёт свободного мастера с нужной специализацией. Учитываются район, рейтинг и нагрузка.",
                    ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF78869C), height: 1.5),
            ),
            const SizedBox(height: 24),
            if (!sent) ...[
              DropdownButtonFormField<String>(
                initialValue: reason,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr(context, "Причина передачи"),
                ),
                items: [
                  for (final r in [
                    'Занят в это время',
                    'Не подходит район',
                    'Не моя специализация',
                    'Другое',
                  ])
                    DropdownMenuItem(value: r, child: Text(tr(context, r))),
                ],
                onChanged: (v) => reason = v!,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: comment,
                maxLength: 150,
                decoration: InputDecoration(
                  labelText: tr(context, "Комментарий"),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        final ok = await mutate(
                          context,
                          ref,
                          () async {
                            await ref
                                .read(apiProvider)
                                .request(
                                  'orders/${widget.id}/transfers/',
                                  method: 'POST',
                                  data: {
                                    'reason':
                                        '$reason${comment.text.trim().isEmpty ? '' : ': ${comment.text.trim()}'}',
                                  },
                                );
                          },
                          message: tr(
                            context,
                            "Система отправила предложение подходящему мастеру",
                          ),
                        );
                        if (mounted) {
                          setState(() {
                            busy = false;
                            sent = ok;
                          });
                        }
                      },
                child: Text(
                  busy
                      ? tr(context, "Подбираем мастера…")
                      : tr(context, "Передать в систему"),
                ),
              ),
            ] else
              FilledButton(
                onPressed: () => context.go('/orders/${widget.id}'),
                child: Text(tr(context, "К заказу")),
              ),
          ],
        ),
      ),
    ],
  );
}
