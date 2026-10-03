import 'translations.dart';
import 'l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'failure.dart';
import 'api.dart';

const blue = Color(0xFF1464F4),
    ink = Color(0xFF152442),
    canvas = Color(0xFFF5F7FB);
ThemeData crmTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: blue,
    primary: blue,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: canvas,
  fontFamily: 'Roboto',
  fontFamilyFallback: const ['Noto Sans'],
  textTheme: const TextTheme(
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF7F9FC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE4E9F2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE4E9F2)),
    ),
    contentPadding: const EdgeInsets.all(16),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    surfaceTintColor: Colors.transparent,
  ),
  dividerTheme: const DividerThemeData(color: Color(0xFFE8EDF5)),
);
String money(Object? value) => value == null
    ? translate(Intl.defaultLocale ?? 'ru', 'Не указана')
    : '${NumberFormat.decimalPattern(Intl.defaultLocale ?? 'ru').format(num.tryParse(value.toString()) ?? 0)} ₸';
String when(DateTime d) =>
    DateFormat('d MMM, HH:mm', Intl.defaultLocale ?? 'ru').format(d.toLocal());
String clock(DateTime d) => DateFormat('HH:mm').format(d.toLocal());
String iso(DateTime d) => d.toUtc().toIso8601String();
const statuses = {
  'NEW': 'Новая заявка',
  'PENDING': 'Ожидает',
  'CONFIRMED': 'Подтверждён',
  'IN_PROGRESS': 'В работе',
  'COMPLETED': 'Выполнен',
  'PAID': 'Оплачен',
  'CANCELLED_CLIENT': 'Отменён клиентом',
  'CANCELLED_MASTER': 'Отменён мастером',
  'TRANSFERRED': 'Передан',
  'REFUNDED': 'Возврат',
  'OFFERED': 'Предложение отправлено',
  'ACCEPTED': 'Принято',
  'DECLINED': 'Отклонено',
  'EXPIRED': 'Истекло',
};

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = ['CONFIRMED', 'COMPLETED', 'PAID', 'ACCEPTED'].contains(status)
        ? const Color(0xFF16866B)
        : status.startsWith('CANCEL') || status == 'DECLINED'
        ? Colors.red
        : status == 'NEW' || status == 'OFFERED'
        ? const Color(0xFFC67D17)
        : blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tr(context, statuses[status] ?? status),
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE9EDF4)),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class PageBody extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? action;
  const PageBody(this.title, {super.key, required this.children, this.action});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 20 : 32,
          ),
          children: [
            Row(
              children: [
                if (context.canPop())
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 24),
            ...children.expand((w) => [w, const SizedBox(height: 16)]),
          ],
        ),
      ),
    ),
  );
}

class Info extends StatelessWidget {
  final IconData icon;
  final String text;
  const Info(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF78869C)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: Color(0xFF66748C))),
        ),
      ],
    ),
  );
}

class Empty extends StatelessWidget {
  final String title, body;
  const Empty(this.title, {super.key, this.body = ''});
  @override
  Widget build(BuildContext context) => Surface(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 35),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 44, color: blue),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(body, textAlign: TextAlign.center),
            ),
        ],
      ),
    ),
  );
}

class AsyncBox<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T) data;
  final VoidCallback retry;
  const AsyncBox({
    super.key,
    required this.value,
    required this.data,
    required this.retry,
  });
  @override
  Widget build(BuildContext context) => value.when(
    skipLoadingOnReload: true,
    data: data,
    loading: () => const Padding(
      padding: EdgeInsets.all(40),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (e, s) => Surface(
      child: Column(
        children: [
          Text(errorText(context, e), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: retry,
            child: Text(tr(context, "Повторить")),
          ),
        ],
      ),
    ),
  );
}

class MoreButton extends ConsumerStatefulWidget {
  final Future<void> Function() load;
  const MoreButton(this.load, {super.key});
  @override
  ConsumerState<MoreButton> createState() => _MoreState();
}

class _MoreState extends ConsumerState<MoreButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: busy
        ? null
        : () async {
            setState(() => busy = true);
            try {
              await widget.load();
            } catch (e) {
              if (context.mounted) showError(context, e);
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
    child: Text(busy ? tr(context, "Загрузка…") : tr(context, "Показать ещё")),
  );
}

String errorText(BuildContext context, Object error) {
  final raw = error is AppFailure ? error.message : error.toString();
  final known =
      translations.containsKey(raw) ||
      translations.values.any((values) => values.containsValue(raw));
  final locale = Localizations.localeOf(context).languageCode;
  final message = known
      ? tr(context, raw)
      : locale == 'ru'
      ? raw
      : tr(context, 'Проверьте введённые данные');
  if (error is! AppFailure || error.fields.isEmpty) return message;
  return '$message\n${error.fields.entries.map((entry) {
    final value = entry.value is List ? (entry.value as List).join('; ') : entry.value.toString();
    return '${entry.key}: ${translations.containsKey(value)
        ? tr(context, value)
        : locale == 'ru'
        ? value
        : tr(context, 'Проверьте введённые данные')}';
  }).join('\n')}';
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(errorText(context, e)),
      backgroundColor: const Color(0xFFB63F47),
    ),
  );
}

Future<bool> mutate(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() fn, {
  String message = 'Сохранено',
}) async {
  try {
    await fn();
    changed(ref);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr(context, message))));
    }
    return true;
  } catch (e) {
    changed(ref);
    if (context.mounted) showError(context, e);
    return false;
  }
}

Future<DateTime?> pickDateTime(BuildContext context, DateTime current) async {
  final date = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime(2020),
    lastDate: DateTime(2040),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(current),
  );
  return time == null
      ? null
      : DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class Avatar extends StatelessWidget {
  final String name;
  const Avatar(this.name, {super.key});
  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: const Color(0xFFDEEAFF),
    foregroundColor: blue,
    child: Text(
      name.isEmpty ? tr(context, "М") : name.substring(0, 1).toUpperCase(),
    ),
  );
}
