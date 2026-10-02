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
              if (u.email != null && u.email!.isNotEmpty) Text(u.email!),
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
                  m.districts.isEmpty ? 'Весь город' : m.districts.join(', '),
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
        if (m != null) const WorkingHoursEditor(),
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

// Keep old bookmarks useful without exposing personal-data editing.
class ProfileFormScreen extends StatelessWidget {
  const ProfileFormScreen({super.key});
  @override
  Widget build(BuildContext context) => const ProfileScreen();
}

class WorkingHoursEditor extends ConsumerStatefulWidget {
  const WorkingHoursEditor({super.key});
  @override
  ConsumerState<WorkingHoursEditor> createState() => _WorkingHoursEditor();
}

class _WorkingHoursEditor extends ConsumerState<WorkingHoursEditor> {
  static const days = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];
  List<List<List<String>>>? hours;
  final enabled = List.filled(7, false);
  bool busy = false;
  String format(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> pick(int day, int interval, int endpoint) async {
    final parts = hours![day][interval][endpoint].split(':');
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time != null && mounted) {
      setState(() => hours![day][interval][endpoint] = format(time));
    }
  }

  @override
  Widget build(BuildContext context) {
    final master = ref.watch(authProvider).valueOrNull?.profile;
    if (master == null) return const SizedBox.shrink();
    hours ??= List.generate(7, (day) {
      final stored = master.workingHours['$day'] as List?;
      final value = stored == null
          ? <List<String>>[
              ['09:00', '18:00'],
            ]
          : stored.map((v) => List<String>.from(v as List)).toList();
      enabled[day] = value.isNotEmpty;
      return value.isEmpty
          ? <List<String>>[
              ['09:00', '18:00'],
            ]
          : value;
    });
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Рабочий график',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Часовой пояс · ${master.timezone}',
            style: const TextStyle(color: Color(0xFF78869C), fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (var day = 0; day < 7; day++) ...[
            Row(
              children: [
                Expanded(child: Text(days[day])),
                Switch(
                  value: enabled[day],
                  activeThumbColor: Colors.white,
                  activeTrackColor: blue,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => enabled[day] = value),
                ),
                SizedBox(
                  width: 136,
                  child: enabled[day]
                      ? intervalRow(day, 0)
                      : const Center(
                          child: Text(
                            'Не работаю',
                            style: TextStyle(color: Color(0xFF78869C)),
                          ),
                        ),
                ),
              ],
            ),
            if (enabled[day]) ...[
              for (var i = 1; i < hours![day].length; i++)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(width: 136, child: intervalRow(day, i)),
                    IconButton(
                      tooltip: 'Удалить интервал',
                      onPressed: busy
                          ? null
                          : () => setState(() => hours![day].removeAt(i)),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy || hours![day].length >= 8
                      ? null
                      : () =>
                            setState(() => hours![day].add(['14:00', '18:00'])),
                  child: const Text('Добавить интервал'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final payload = <String, List<List<String>>>{};
                    for (var day = 0; day < 7; day++) {
                      final intervals = enabled[day]
                          ? hours![day]
                                .map((v) => List<String>.from(v))
                                .toList()
                          : <List<String>>[];
                      intervals.sort((a, b) => a[0].compareTo(b[0]));
                      for (var i = 0; i < intervals.length; i++) {
                        if (intervals[i][0].compareTo(intervals[i][1]) >= 0 ||
                            (i > 0 &&
                                intervals[i][0].compareTo(intervals[i - 1][1]) <
                                    0)) {
                          showError(
                            context,
                            Exception(
                              '${days[day]}: проверьте время и пересечение интервалов',
                            ),
                          );
                          return;
                        }
                      }
                      payload['$day'] = intervals;
                    }
                    setState(() => busy = true);
                    final ok = await mutate(context, ref, () async {
                      await ref
                          .read(apiProvider)
                          .request(
                            'me/',
                            method: 'PATCH',
                            data: {
                              'master_profile': {'working_hours': payload},
                            },
                          );
                      await ref.read(authProvider.notifier).reload();
                    });
                    if (mounted) {
                      setState(() => busy = false);
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Рабочий график сохранён'),
                          ),
                        );
                      }
                    }
                  },
            child: Text(busy ? 'Сохраняем…' : 'Сохранить график'),
          ),
        ],
      ),
    );
  }

  Widget intervalRow(int day, int interval) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var endpoint = 0; endpoint < 2; endpoint++) ...[
        if (endpoint == 1) const Text('–'),
        Expanded(
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(54, 36),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            onPressed: busy ? null : () => pick(day, interval, endpoint),
            child: FittedBox(child: Text(hours![day][interval][endpoint])),
          ),
        ),
      ],
    ],
  );
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
