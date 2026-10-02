import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';
import '../../../core/ui.dart';
import '../../../core/catalogs.dart';
import 'providers.dart';
import '../../orders/presentation/orders.dart';

class ClientsScreen extends ConsumerWidget {
  const ClientsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    'Клиенты',
    action: IconButton(
      onPressed: () => context.push('/clients/new'),
      icon: const Icon(Icons.person_add_alt, color: blue),
    ),
    children: [
      TextField(
        decoration: const InputDecoration(
          hintText: 'Поиск клиента…',
          prefixIcon: Icon(Icons.search),
        ),
        onSubmitted: (v) => ref.read(clientsFilter.notifier).state =
            v.trim().isEmpty ? {} : {'search': v.trim()},
      ),
      AsyncBox(
        value: ref.watch(clientsProvider),
        retry: () => ref.invalidate(clientsProvider),
        data: (p) => p.items.isEmpty
            ? const Empty('Клиентов пока нет')
            : Column(
                children: [
                  Surface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final c in p.items)
                          ListTile(
                            leading: Avatar(c.label),
                            title: Text(c.label),
                            subtitle: Text(c.phone),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/clients/${c.id}'),
                          ),
                      ],
                    ),
                  ),
                  if (p.hasNext)
                    MoreButton(ref.read(clientsProvider.notifier).more),
                ],
              ),
      ),
      FilledButton.icon(
        onPressed: () => context.push('/clients/new'),
        icon: const Icon(Icons.add),
        label: const Text('Добавить клиента'),
      ),
    ],
  );
}

final clientOrdersProvider = FutureProvider.family<List<OrderDto>, String>((
  ref,
  id,
) {
  ref.watch(revisionProvider);
  ref.watch(liveRevisionProvider);
  return ref.read(apiProvider).all('clients/$id/orders/', OrderDto.fromJson);
});

class ClientDetailScreen extends ConsumerWidget {
  final String id;
  const ClientDetailScreen(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    'Клиент',
    action: IconButton(
      onPressed: () => context.push('/clients/$id/edit'),
      icon: const Icon(Icons.edit_outlined),
    ),
    children: [
      AsyncBox(
        value: ref.watch(clientProvider(id)),
        retry: () => ref.invalidate(clientProvider(id)),
        data: (c) => Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(c.label),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      c.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Info(Icons.phone_outlined, c.phone),
              Info(Icons.source_outlined, 'Источник: ${c.source}'),
              const Divider(),
              const Text(
                'Заметки',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(c.notes.isEmpty ? 'Нет заметок' : c.notes),
            ],
          ),
        ),
      ),
      FilledButton.icon(
        onPressed: () => context.push('/orders/new?client=$id'),
        icon: const Icon(Icons.add),
        label: const Text('Добавить заказ'),
      ),
      Text('История заказов', style: Theme.of(context).textTheme.titleLarge),
      AsyncBox(
        value: ref.watch(clientOrdersProvider(id)),
        retry: () => ref.invalidate(clientOrdersProvider(id)),
        data: (orders) => orders.isEmpty
            ? const Empty('Заказов ещё нет')
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
    ],
  );
}

class ClientFormScreen extends ConsumerStatefulWidget {
  final String? id;
  const ClientFormScreen({super.key, this.id});
  @override
  ConsumerState<ClientFormScreen> createState() => _ClientForm();
}

class _ClientForm extends ConsumerState<ClientFormScreen> {
  final key = GlobalKey<FormState>(),
      name = TextEditingController(),
      phone = TextEditingController(),
      notes = TextEditingController();
  bool busy = false, loaded = false;
  String source = 'MANUAL';
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    setState(() => busy = true);
    final ok = await mutate(context, ref, () async {
      final c =
          await ResourceRepository(
            ref.read(apiProvider),
            'clients/',
            ClientDto.fromJson,
          ).save({
            'name': name.text.trim(),
            'phone': phone.text.trim(),
            'notes': notes.text.trim(),
            'source': source,
          }, id: widget.id);
      if (mounted) {
        if (context.canPop()) {
          context.pop(c.id);
        } else {
          context.go('/clients/${c.id}');
        }
      }
    });
    if (mounted) setState(() => busy = false);
    if (!ok) return;
  }

  Widget form(ClientDto? c) {
    if (!loaded) {
      if (c != null) {
        name.text = c.name ?? '';
        phone.text = c.phone;
        notes.text = c.notes;
        source = c.source;
      }
      loaded = true;
    }
    return Form(
      key: key,
      child: Column(
        children: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Телефон *'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Введите телефон' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: source,
            decoration: const InputDecoration(labelText: 'Источник'),
            items: [
              for (final s in ['MANUAL', 'BOT', 'TRANSFER', 'OTHER'])
                DropdownMenuItem(
                  value: s,
                  child: Text(
                    {
                      'MANUAL': 'Вручную',
                      'BOT': 'Бот',
                      'TRANSFER': 'Передача',
                      'OTHER': 'Другое',
                    }[s]!,
                  ),
                ),
            ],
            onChanged: (s) => source = s!,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: notes,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Заметки'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Сохраняем…' : 'Сохранить'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageBody(
    widget.id == null ? 'Добавить клиента' : 'Редактировать клиента',
    children: [
      Surface(
        child: widget.id == null
            ? form(null)
            : AsyncBox(
                value: ref.watch(clientProvider(widget.id!)),
                retry: () => ref.invalidate(clientProvider(widget.id!)),
                data: form,
              ),
      ),
    ],
  );
}
