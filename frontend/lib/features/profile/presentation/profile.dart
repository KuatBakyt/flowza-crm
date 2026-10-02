import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api.dart';
import '../../../core/ui.dart';
import '../../../core/catalogs.dart';
import '../../auth/presentation/auth.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _Profile();
}

class _Profile extends ConsumerState<ProfileScreen> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final u = ref.watch(authProvider).valueOrNull;
    if (u == null) return const SizedBox.shrink();
    final m = u.profile;
    final skills = ref.watch(skillsCatalog).valueOrNull ?? [];
    return PageBody(
      'Профиль',
      action: IconButton(
        onPressed: () => context.push('/profile/edit'),
        icon: const Icon(Icons.edit_outlined, color: blue),
      ),
      children: [
        Surface(
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFFE3EDFF),
                child: Text(
                  u.name.substring(0, 1),
                  style: const TextStyle(fontSize: 28, color: blue),
                ),
              ),
              const SizedBox(height: 16),
              Text(u.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(u.phone),
              if (m != null) ...[
                const SizedBox(height: 10),
                Text(
                  '★ ${m.internalRating} · ${m.completedOrdersCount} выполнено',
                  style: const TextStyle(color: Color(0xFFC98B1A)),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Принимать заказы'),
                  subtitle: Text(
                    m.isAvailable
                        ? 'Вы доступны для новых заказов'
                        : 'Новые передачи отключены',
                  ),
                  value: m.isAvailable,
                  onChanged: busy
                      ? null
                      : (value) async {
                          setState(() => busy = true);
                          await mutate(context, ref, () async {
                            await ref
                                .read(apiProvider)
                                .request(
                                  'me/',
                                  method: 'PATCH',
                                  data: {
                                    'master_profile': {'is_available': value},
                                  },
                                );
                            await ref.read(authProvider.notifier).reload();
                          });
                          if (mounted) setState(() => busy = false);
                        },
                ),
              ],
            ],
          ),
        ),
        if (m != null)
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Info(Icons.build_outlined, 'Специализации'),
                for (final skill in m.skills.where(
                  (s) => s['is_active'] == true,
                ))
                  Padding(
                    padding: const EdgeInsets.only(left: 28, bottom: 8),
                    child: Text(
                      skills
                                  .where(
                                    (s) => s['id'] == skill['specialization'],
                                  )
                                  .firstOrNull?['name']
                              as String? ??
                          'Специализация',
                    ),
                  ),
                const Divider(),
                Info(Icons.location_city_outlined, m.city),
                Info(
                  Icons.place_outlined,
                  m.districts.isEmpty
                      ? 'Районы не указаны'
                      : m.districts.join(', '),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.beach_access_outlined, color: blue),
                  title: const Text('Отпуск / выходной'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/schedule/new'),
                ),
                const Text(
                  'Специализации назначает администратор. Отпуск отмечается блоком занятости.',
                  style: TextStyle(color: Color(0xFF78869C), fontSize: 12),
                ),
              ],
            ),
          ),
        if (u.admin)
          OutlinedButton.icon(
            onPressed: () async {
              final base = ref.read(apiProvider).dio.options.baseUrl;
              final uri = Uri.parse(base).resolve('/admin/');
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
                  context.mounted) {
                showError(context, Exception('Не удалось открыть админку'));
              }
            },
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Django admin'),
          ),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await ref.read(authProvider.notifier).logout();
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                  if (mounted) setState(() => busy = false);
                },
          icon: const Icon(Icons.logout),
          label: const Text('Выйти'),
        ),
      ],
    );
  }
}

class ProfileFormScreen extends ConsumerStatefulWidget {
  const ProfileFormScreen({super.key});
  @override
  ConsumerState<ProfileFormScreen> createState() => _ProfileForm();
}

class _ProfileForm extends ConsumerState<ProfileFormScreen> {
  final key = GlobalKey<FormState>(),
      name = TextEditingController(),
      phone = TextEditingController(),
      email = TextEditingController(),
      city = TextEditingController(),
      districts = TextEditingController();
  bool loaded = false, busy = false;
  @override
  void dispose() {
    for (final c in [name, phone, email, city, districts]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = ref.watch(authProvider).valueOrNull;
    if (u == null) return const SizedBox.shrink();
    if (!loaded) {
      name.text = u.name;
      phone.text = u.phone;
      email.text = u.email ?? '';
      city.text = u.profile?.city ?? '';
      districts.text = u.profile?.districts.join(', ') ?? '';
      loaded = true;
    }
    return PageBody(
      'Редактировать профиль',
      children: [
        Surface(
          child: Form(
            key: key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (u.profile != null) ...[
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Имя *'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Введите имя' : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Телефон *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Введите телефон' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                if (u.profile != null) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: city,
                    decoration: const InputDecoration(labelText: 'Город'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: districts,
                    decoration: const InputDecoration(
                      labelText: 'Районы через запятую',
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!key.currentState!.validate()) return;
                          setState(() => busy = true);
                          final ok = await mutate(context, ref, () async {
                            await ref
                                .read(apiProvider)
                                .request(
                                  'me/',
                                  method: 'PATCH',
                                  data: {
                                    'phone': phone.text.trim(),
                                    'email': email.text.trim().isEmpty
                                        ? null
                                        : email.text.trim(),
                                    if (u.profile != null)
                                      'master_profile': {
                                        'full_name': name.text.trim(),
                                        'city': city.text.trim(),
                                        'districts': districts.text
                                            .split(',')
                                            .map((s) => s.trim())
                                            .where((s) => s.isNotEmpty)
                                            .toList(),
                                      },
                                  },
                                );
                            await ref.read(authProvider.notifier).reload();
                          });
                          if (mounted && context.mounted) {
                            setState(() => busy = false);
                            if (ok) context.pop();
                          }
                        },
                  child: Text(busy ? 'Сохраняем…' : 'Сохранить'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) => PageBody(
    'Ещё',
    children: [
      Surface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final entry in [
              ('Клиенты', Icons.people_outline, '/clients'),
              ('Предложения заказов', Icons.swap_horiz, '/transfers'),
              ('Статистика', Icons.bar_chart, '/statistics'),
              ('Уведомления', Icons.notifications_outlined, '/notifications'),
              ('Профиль', Icons.person_outline, '/profile'),
            ])
              ListTile(
                leading: Icon(entry.$2, color: blue),
                title: Text(entry.$1),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(entry.$3),
              ),
          ],
        ),
      ),
    ],
  );
}
