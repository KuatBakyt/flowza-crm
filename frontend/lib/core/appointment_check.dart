import 'package:flutter/material.dart';

import 'api.dart';
import 'failure.dart';
import 'ui.dart';

Future<bool> checkAppointment(
  BuildContext context,
  ApiClient api,
  String master,
  DateTime start,
  DateTime end, {
  String? excludeOrder,
}) async {
  final result = await api.request(
    'schedule/check/',
    method: 'POST',
    data: {
      'master_id': master,
      'start_at': iso(start),
      'end_at': iso(end),
      if (excludeOrder != null) 'exclude_order': excludeOrder,
    },
  );
  if (result['available'] != true) {
    throw const AppFailure(
      code: 'schedule_conflict',
      message: 'Время уже занято. Выберите другой интервал.',
    );
  }
  if (!context.mounted) return false;
  if (result['within_working_hours'] != false) return true;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Вне рабочего графика'),
          content: const Text(
            'Это время вне рабочего графика мастера. Всё равно назначить заказ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Выбрать другое время'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Всё равно назначить'),
            ),
          ],
        ),
      ) ??
      false;
}
