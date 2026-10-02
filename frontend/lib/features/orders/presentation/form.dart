import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';
import '../../../core/ui.dart';
import '../../../core/catalogs.dart';
import '../../../core/failure.dart';
import '../../auth/presentation/auth.dart';

class OrderFormScreen extends ConsumerStatefulWidget {
  final String? id, client;
  final DateTime? start;
  const OrderFormScreen({super.key, this.id, this.client, this.start});
  @override
  ConsumerState<OrderFormScreen> createState() => _OrderForm();
}

class _OrderForm extends ConsumerState<OrderFormScreen> {
  final key = GlobalKey<FormState>();
  final title = TextEditingController(),
      description = TextEditingController(),
      address = TextEditingController(),
      district = TextEditingController(),
      price = TextEditingController();
  String? client, skill, master;
  late DateTime start, end;
  bool loaded = false, busy = false;
  @override
  void initState() {
    super.initState();
    client = widget.client;
    start = widget.start ?? DateTime.now().add(const Duration(days: 1));
    start = DateTime(start.year, start.month, start.day, start.hour);
    end = start.add(const Duration(hours: 2));
  }

  @override
  void dispose() {
    for (final c in [title, description, address, district, price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save(OrderDto? o) async {
    if (!key.currentState!.validate()) return;
    if (!start.isBefore(end)) {
      showError(
        context,
        const AppFailure(
          code: 'date',
          message: 'Начало должно быть раньше окончания',
        ),
      );
      return;
    }
    setState(() => busy = true);
    await mutate(context, ref, () async {
      final api = ref.read(apiProvider), u = ref.read(authProvider).valueOrNull;
      final active = o?.status == 'CONFIRMED';
      if (!active) {
        final m = u!.admin ? master : u.profile?.id;
        if (m != null) {
          final check = await api.request(
            'schedule/check/',
            method: 'POST',
            data: {'master_id': m, 'start_at': iso(start), 'end_at': iso(end)},
          );
          if (check['available'] != true) {
            throw const AppFailure(
              code: 'schedule_conflict',
              message: 'Время уже занято. Выберите другой интервал.',
            );
          }
        }
      }
      final body = <String, dynamic>{
        'client': client,
        'title': title.text.trim(),
        'description': description.text.trim(),
        'address': address.text.trim(),
        'district': district.text.trim(),
        'estimated_price': price.text.trim().isEmpty
            ? null
            : price.text.trim().replaceAll(',', '.'),
      };
      if (!active) {
        body.addAll({
          'specialization': skill,
          'start_at': iso(start),
          'end_at': iso(end),
        });
        if (u!.admin) body['master'] = master;
      }
      if (o == null) body['source'] = 'MANUAL';
      final saved = await ResourceRepository(
        api,
        'orders/',
        OrderDto.fromJson,
      ).save(body, id: widget.id);
      if (mounted) context.go('/orders/${saved.id}');
    });
    if (mounted) setState(() => busy = false);
  }

  Widget form(OrderDto? o) {
    if (!loaded) {
      if (o != null) {
        title.text = o.title;
        description.text = o.description;
        address.text = o.address;
        district.text = o.district;
        price.text = o.estimatedPrice ?? '';
        client = o.client;
        skill = o.specialization;
        master = o.master;
        start = o.startAt.toLocal();
        end = o.endAt.toLocal();
      }
      loaded = true;
    }
    final clients = ref.watch(clientsCatalog),
        skills = ref.watch(skillsCatalog),
        masters = ref.watch(mastersCatalog),
        u = ref.watch(authProvider).valueOrNull;
    final active = o?.status == 'CONFIRMED';
    final choices = skills.valueOrNull ?? [];
    final allowed = u?.admin == true
        ? choices
        : choices
              .where(
                (s) =>
                    u?.profile?.skills.any(
                      (k) =>
                          k['specialization'] == s['id'] &&
                          k['is_active'] == true,
                    ) ==
                    true,
              )
              .toList();
    return Form(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AsyncBox(
            value: clients,
            retry: () => ref.invalidate(clientsCatalog),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: list.any((c) => c.id == client) ? client : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Клиент *'),
              items: [
                for (final c in list)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => client = v,
              validator: (v) => v == null ? 'Выберите клиента' : null,
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final id = await context.push<String>('/clients/new');
              if (id != null && mounted) setState(() => client = id);
            },
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Добавить нового клиента'),
          ),
          TextFormField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Название услуги *'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Введите название' : null,
          ),
          const SizedBox(height: 16),
          if (!active)
            AsyncBox(
              value: skills,
              retry: () => ref.invalidate(skillsCatalog),
              data: (_) => DropdownButtonFormField<String>(
                initialValue: allowed.any((s) => s['id'] == skill)
                    ? skill
                    : null,
                decoration: const InputDecoration(labelText: 'Специализация *'),
                isExpanded: true,
                items: [
                  for (final s in allowed)
                    DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text(s['name'] as String),
                    ),
                ],
                onChanged: (v) => skill = v,
                validator: (v) => v == null ? 'Выберите специализацию' : null,
              ),
            ),
          if (u?.admin == true && !active) ...[
            const SizedBox(height: 16),
            AsyncBox(
              value: masters,
              retry: () => ref.invalidate(mastersCatalog),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: list.any((m) => m.id == master) ? master : null,
                decoration: const InputDecoration(labelText: 'Мастер *'),
                isExpanded: true,
                items: [
                  for (final m in list)
                    DropdownMenuItem(value: m.id, child: Text(m.fullName)),
                ],
                onChanged: (v) => master = v,
                validator: (v) => v == null ? 'Назначьте мастера' : null,
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Описание работ'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: address,
            decoration: const InputDecoration(labelText: 'Адрес *'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Введите адрес' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: district,
            decoration: const InputDecoration(labelText: 'Район'),
          ),
          const SizedBox(height: 16),
          if (!active) ...[
            OutlinedButton.icon(
              onPressed: () async {
                final d = await pickDateTime(context, start);
                if (d != null) setState(() => start = d);
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Начало: ${when(start)}'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await pickDateTime(context, end);
                if (d != null) setState(() => end = d);
              },
              icon: const Icon(Icons.schedule),
              label: Text('Окончание: ${when(end)}'),
            ),
          ] else
            const Text(
              'Для изменения времени подтверждённого заказа используйте «Перенести» в карточке.',
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Ориентировочная стоимость, ₸',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = num.tryParse(v.replaceAll(',', '.'));
              return n == null || n < 0 ? 'Введите сумму от 0' : null;
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : () => save(o),
            child: Text(busy ? 'Сохраняем…' : 'Сохранить заказ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageBody(
    widget.id == null ? 'Новый заказ' : 'Редактировать заказ',
    children: [
      Surface(
        child: widget.id == null
            ? form(null)
            : AsyncBox(
                value: ref.watch(orderProvider(widget.id!)),
                retry: () => ref.invalidate(orderProvider(widget.id!)),
                data: form,
              ),
      ),
    ],
  );
}
