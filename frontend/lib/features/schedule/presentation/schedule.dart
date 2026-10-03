import '../../../core/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';
import '../../../core/ui.dart';
import '../../../core/catalogs.dart';
import '../../auth/presentation/auth.dart';

final calendarDate = StateProvider<DateTime>((ref) {
  final d = DateTime.now();
  return DateTime(d.year, d.month, d.day);
});
final calendarWeek = StateProvider<bool>((ref) => false);
final calendarMaster = StateProvider<String?>((ref) => null);
final scheduleProvider = FutureProvider<List<BlockDto>>((ref) {
  ref.watch(revisionProvider);
  ref.watch(liveRevisionProvider);
  final d = ref.watch(calendarDate), week = ref.watch(calendarWeek);
  final from = week ? d.subtract(Duration(days: d.weekday - 1)) : d;
  return ref
      .read(apiProvider)
      .all(
        'schedule/',
        BlockDto.fromJson,
        query: {
          'from': iso(from),
          'to': iso(from.add(Duration(days: week ? 7 : 1))),
        },
      );
});

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(calendarDate),
        week = ref.watch(calendarWeek),
        master = ref.watch(calendarMaster),
        admin = ref.watch(authProvider).valueOrNull?.admin == true;
    final start = week ? d.subtract(Duration(days: d.weekday - 1)) : d;
    return PageBody(
      tr(context, "Календарь"),
      action: IconButton(
        onPressed: () => context.push(
          '/schedule/new?start=${Uri.encodeComponent(iso(d.add(const Duration(hours: 9))))}',
        ),
        icon: const Icon(Icons.add_circle_outline, color: blue),
      ),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => ref.read(calendarDate.notifier).state = d
                  .subtract(Duration(days: week ? 7 : 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: d,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (value != null) {
                    ref.read(calendarDate.notifier).state = value;
                  }
                },
                child: Text(
                  DateFormat(
                    'd MMMM yyyy',
                    Localizations.localeOf(context).languageCode,
                  ).format(d),
                ),
              ),
            ),
            IconButton(
              onPressed: () => ref.read(calendarDate.notifier).state = d.add(
                Duration(days: week ? 7 : 1),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(tr(context, "День")),
              icon: Icon(Icons.view_day_outlined),
            ),
            ButtonSegment(
              value: true,
              label: Text(tr(context, "Неделя")),
              icon: Icon(Icons.view_week_outlined),
            ),
          ],
          selected: {week},
          onSelectionChanged: (v) =>
              ref.read(calendarWeek.notifier).state = v.first,
        ),
        if (admin)
          AsyncBox(
            value: ref.watch(mastersCatalog),
            retry: () => ref.invalidate(mastersCatalog),
            data: (list) => DropdownButtonFormField<String>(
              initialValue: master,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr(context, "Мастер")),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(tr(context, "Все мастера")),
                ),
                for (final m in list)
                  DropdownMenuItem(value: m.id, child: Text(m.fullName)),
              ],
              onChanged: (v) => ref.read(calendarMaster.notifier).state = v,
            ),
          ),
        AsyncBox(
          value: ref.watch(scheduleProvider),
          retry: () => ref.invalidate(scheduleProvider),
          data: (items) {
            final blocks = items
                .where((b) => master == null || b.master == master)
                .toList();
            if (!week) return DayTimeline(d, blocks);
            return Column(
              children: [
                for (var day = 0; day < (week ? 7 : 1); day++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat(
                              'EEEE, d MMMM',
                              Localizations.localeOf(context).languageCode,
                            ).format(start.add(Duration(days: day))),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          ...blocks
                              .where(
                                (b) =>
                                    b.startAt.toLocal().isBefore(
                                      start.add(Duration(days: day + 1)),
                                    ) &&
                                    b.endAt.toLocal().isAfter(
                                      start.add(Duration(days: day)),
                                    ),
                              )
                              .map((b) => BlockCard(b)),
                          if (!blocks.any(
                            (b) =>
                                b.startAt.toLocal().isBefore(
                                  start.add(Duration(days: day + 1)),
                                ) &&
                                b.endAt.toLocal().isAfter(
                                  start.add(Duration(days: day)),
                                ),
                          ))
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                tr(context, "Нет занятости"),
                                style: TextStyle(color: Color(0xFF78869C)),
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => context.push(
                              '/schedule/new?start=${Uri.encodeComponent(iso(start.add(Duration(days: day, hours: 9))))}',
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(tr(context, "Добавить занятость")),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (!admin)
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final slots = await ref
                    .read(apiProvider)
                    .request(
                      'schedule/free-slots/',
                      query: {'date': DateFormat('yyyy-MM-dd').format(d)},
                    );
                if (context.mounted) {
                  await showDialog<void>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(tr(context, "Свободные интервалы")),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final s in slots as List)
                              Text(
                                '${clock(DateTime.parse(s['start_at'] as String))} – ${clock(DateTime.parse(s['end_at'] as String))}',
                              ),
                            if (slots.isEmpty)
                              Text(tr(context, "Свободных интервалов нет")),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: Text(tr(context, "Закрыть")),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            icon: const Icon(Icons.event_available),
            label: Text(tr(context, "Свободное время")),
          ),
      ],
    );
  }
}

class BlockCard extends ConsumerWidget {
  final BlockDto block;
  const BlockCard(this.block, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = block,
        color = b.type == 'ORDER'
            ? const Color(0xFFDDF4EA)
            : b.type == 'UNAVAILABLE'
            ? const Color(0xFFFFEBDC)
            : const Color(0xFFE2EBFF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: Icon(
            b.type == 'ORDER'
                ? Icons.work_outline
                : b.type == 'UNAVAILABLE'
                ? Icons.beach_access_outlined
                : Icons.event_busy,
            color: blue,
          ),
          title: Text(
            b.note?.isNotEmpty == true
                ? b.note!
                : b.type == 'ORDER'
                ? tr(context, "Заказ")
                : tr(context, "Занятость"),
          ),
          subtitle: Text('${when(b.startAt)} – ${when(b.endAt)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => b.order != null
              ? context.push('/orders/${b.order}')
              : context.push('/schedule/new', extra: b),
        ),
      ),
    );
  }
}

class BlockFormScreen extends ConsumerStatefulWidget {
  final BlockDto? block;
  final DateTime? start;
  const BlockFormScreen({super.key, this.block, this.start});
  @override
  ConsumerState<BlockFormScreen> createState() => _BlockForm();
}

class _BlockForm extends ConsumerState<BlockFormScreen> {
  final key = GlobalKey<FormState>(), note = TextEditingController();
  late DateTime start, end;
  String type = 'MANUAL';
  String? master;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final b = widget.block;
    start =
        b?.startAt.toLocal() ??
        widget.start?.toLocal() ??
        DateTime.now().add(const Duration(hours: 1));
    end = b?.endAt.toLocal() ?? start.add(const Duration(hours: 1));
    note.text = b?.note ?? '';
    type = b?.type ?? 'MANUAL';
    master = b?.master;
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    if (!start.isBefore(end)) {
      showError(
        context,
        Exception(tr(context, "Начало должно быть раньше окончания")),
      );
      return;
    }
    setState(() => busy = true);
    final ok = await mutate(context, ref, () async {
      final api = ref.read(apiProvider);
      await api.request(
        widget.block == null
            ? 'schedule/blocks/'
            : 'schedule/blocks/${widget.block!.id}/',
        method: widget.block == null ? 'POST' : 'PATCH',
        data: {
          'start_at': iso(start),
          'end_at': iso(end),
          'type': type,
          'note': note.text.trim(),
          if (ref.read(authProvider).valueOrNull?.admin == true &&
              widget.block == null)
            'master': master,
        },
      );
    });
    if (mounted && context.mounted) {
      setState(() => busy = false);
      if (ok) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/schedule');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    widget.block == null
        ? tr(context, "Добавить занятость")
        : tr(context, "Редактировать занятость"),
    children: [
      Surface(
        child: Form(
          key: key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'MANUAL',
                    label: Text(tr(context, "Личная")),
                  ),
                  ButtonSegment(
                    value: 'UNAVAILABLE',
                    label: Text(tr(context, "Отпуск / выходной")),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (v) => setState(() => type = v.first),
              ),
              const SizedBox(height: 20),
              if (ref.watch(authProvider).valueOrNull?.admin == true &&
                  widget.block == null) ...[
                AsyncBox(
                  value: ref.watch(mastersCatalog),
                  retry: () => ref.invalidate(mastersCatalog),
                  data: (list) => DropdownButtonFormField<String>(
                    initialValue: master,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr(context, "Мастер *"),
                    ),
                    items: [
                      for (final m in list)
                        DropdownMenuItem(value: m.id, child: Text(m.fullName)),
                    ],
                    onChanged: (v) => master = v,
                    validator: (v) =>
                        v == null ? tr(context, "Выберите мастера") : null,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: note,
                decoration: InputDecoration(
                  labelText: tr(context, "Название или комментарий"),
                ),
                maxLength: 255,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await pickDateTime(context, start);
                  if (d != null) setState(() => start = d);
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(tr(context, "Начало: {0}", [when(start)])),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await pickDateTime(context, end);
                  if (d != null) setState(() => end = d);
                },
                icon: const Icon(Icons.schedule),
                label: Text(tr(context, "Окончание: {0}", [when(end)])),
              ),
              const SizedBox(height: 20),
              Text(
                tr(
                  context,
                  "В этот период новые заказы не смогут занять ваше время.",
                ),
                style: TextStyle(color: Color(0xFF78869C)),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : save,
                child: Text(
                  busy ? tr(context, "Сохраняем…") : tr(context, "Сохранить"),
                ),
              ),
              if (widget.block != null)
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: Text(tr(context, "Удалить занятость?")),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: Text(tr(context, "Назад")),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: Text(tr(context, "Удалить")),
                                ),
                              ],
                            ),
                          );
                          if (yes != true || !context.mounted) return;
                          setState(() => busy = true);
                          final ok = await mutate(context, ref, () async {
                            await ref
                                .read(apiProvider)
                                .request(
                                  'schedule/blocks/${widget.block!.id}/',
                                  method: 'DELETE',
                                );
                          });
                          if (mounted && context.mounted) {
                            setState(() => busy = false);
                            if (ok) context.pop();
                          }
                        },
                  child: Text(
                    tr(context, "Удалить блок"),
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class DayTimeline extends ConsumerStatefulWidget {
  final DateTime day;
  final List<BlockDto> blocks;
  const DayTimeline(this.day, this.blocks, {super.key});
  @override
  ConsumerState<DayTimeline> createState() => _Timeline();
}

class _Timeline extends ConsumerState<DayTimeline> {
  final scroll = ScrollController(initialScrollOffset: 8 * 64);
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.day.add(const Duration(days: 1));
    final items =
        widget.blocks
            .where(
              (b) =>
                  b.startAt.toLocal().isBefore(end) &&
                  b.endAt.toLocal().isAfter(widget.day),
            )
            .toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final lanes = <DateTime>[], assigned = <int>[];
    for (final b in items) {
      var lane = lanes.indexWhere((e) => !e.isAfter(b.startAt));
      if (lane < 0) {
        lane = lanes.length;
        lanes.add(b.endAt);
      } else {
        lanes[lane] = b.endAt;
      }
      assigned.add(lane);
    }
    return Surface(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 500,
        child: SingleChildScrollView(
          controller: scroll,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final width =
                  (bounds.maxWidth - 48) / (lanes.isEmpty ? 1 : lanes.length);
              return SizedBox(
                height: 24 * 64,
                child: Stack(
                  children: [
                    for (var hour = 0; hour < 24; hour++)
                      Positioned(
                        top: hour * 64,
                        left: 0,
                        right: 0,
                        height: 64,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 48,
                              child: Text(
                                '${hour.toString().padLeft(2, '0')}:00',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF78869C),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => chooseFree(
                                  context,
                                  widget.day.add(Duration(hours: hour)),
                                ),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: Color(0xFFE8EDF5)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (var i = 0; i < items.length; i++)
                      position(items[i], assigned[i], width),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget position(BlockDto b, int lane, double width) {
    final from =
        b.startAt.toLocal().difference(widget.day).inMinutes.clamp(0, 1440) /
        60 *
        64;
    final to =
        b.endAt.toLocal().difference(widget.day).inMinutes.clamp(0, 1440) /
        60 *
        64;
    final title = b.note?.isNotEmpty == true
        ? b.note!
        : b.order != null
        ? ref.watch(orderProvider(b.order!)).valueOrNull?.title ??
              tr(context, "Заказ")
        : tr(context, "Занятость");
    return Positioned(
      top: from + 2,
      left: 48 + lane * width,
      width: width - 4,
      height: (to - from - 4).clamp(20, 1532).toDouble(),
      child: Material(
        color: b.type == 'ORDER'
            ? const Color(0xFFDCF4EA)
            : b.type == 'UNAVAILABLE'
            ? const Color(0xFFFFEBDC)
            : const Color(0xFFDFE9FF),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => b.order != null
              ? context.push('/orders/${b.order}')
              : context.push('/schedule/new', extra: b),
          child: ClipRect(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${clock(b.startAt)} – ${clock(b.endAt)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> chooseFree(BuildContext context, DateTime start) async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_task, color: blue),
              title: Text(tr(context, "Новый заказ")),
              onTap: () => Navigator.pop(c, '/orders/new'),
            ),
            ListTile(
              leading: const Icon(Icons.event_busy, color: blue),
              title: Text(tr(context, "Личная занятость")),
              onTap: () => Navigator.pop(c, '/schedule/new'),
            ),
          ],
        ),
      ),
    );
    if (kind != null && context.mounted) {
      context.push('$kind?start=${Uri.encodeComponent(iso(start))}');
    }
  }
}
