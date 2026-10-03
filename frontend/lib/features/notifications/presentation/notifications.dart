import '../../../core/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/ui.dart';
import 'providers.dart';

final unreadProvider = FutureProvider<int>((ref) async {
  ref.watch(revisionProvider);
  ref.watch(liveRevisionProvider);
  final j = await ref
      .read(apiProvider)
      .request('notifications/', query: {'is_read': 'false'});
  return j['count'] as int;
});

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _Notifications();
}

class _Notifications extends ConsumerState<NotificationsScreen> {
  String? busy;
  @override
  Widget build(BuildContext context) => PageBody(
    tr(context, "Уведомления"),
    children: [
      Row(
        children: [
          FilterChip(
            label: Text(tr(context, "Непрочитанные")),
            selected: ref.watch(notificationsFilter)['is_read'] == 'false',
            onSelected: (v) => ref.read(notificationsFilter.notifier).state = v
                ? {'is_read': 'false'}
                : {},
          ),
          const Spacer(),
          ref
              .watch(unreadProvider)
              .maybeWhen(
                data: (n) => Text(tr(context, "{0} новых", [n])),
                orElse: () => const SizedBox.shrink(),
              ),
        ],
      ),
      AsyncBox(
        value: ref.watch(notificationsProvider),
        retry: () => ref.invalidate(notificationsProvider),
        data: (p) => p.items.isEmpty
            ? Empty(tr(context, "Уведомлений нет"))
            : Column(
                children: [
                  for (final n in p.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Surface(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: n.isRead
                                ? canvas
                                : const Color(0xFFE3EDFF),
                            child: Icon(
                              Icons.notifications_outlined,
                              color: n.isRead ? Colors.grey : blue,
                            ),
                          ),
                          title: Text(
                            tr(context, n.title),
                            style: TextStyle(
                              fontWeight: n.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('${n.body}\n${when(n.createdAt)}'),
                          ),
                          trailing: n.isRead
                              ? null
                              : const Icon(Icons.circle, size: 8, color: blue),
                          onTap: busy != null
                              ? null
                              : () async {
                                  setState(() => busy = n.id);
                                  if (!n.isRead) {
                                    await mutate(context, ref, () async {
                                      await ref
                                          .read(apiProvider)
                                          .request(
                                            'notifications/${n.id}/read/',
                                            method: 'POST',
                                            data: {},
                                          );
                                    }, message: tr(context, "Прочитано"));
                                  }
                                  if (mounted && context.mounted) {
                                    setState(() => busy = null);
                                    final id =
                                        n.payload['order_id'] ??
                                        n.payload['order'];
                                    if (n.payload['transfer_id'] != null) {
                                      context.push('/transfers');
                                    } else if (id is String) {
                                      context.push('/orders/$id');
                                    }
                                  }
                                },
                        ),
                      ),
                    ),
                  if (p.hasNext)
                    MoreButton(ref.read(notificationsProvider.notifier).more),
                ],
              ),
      ),
    ],
  );
}
