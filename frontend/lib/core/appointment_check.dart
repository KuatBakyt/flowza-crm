import 'l10n.dart';

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
  if (!context.mounted) return false;
  if (result['available'] != true) {
    throw AppFailure(
      code: 'schedule_conflict',
      message: tr(context, "Время уже занято. Выберите другой интервал."),
    );
  }
  if (result['within_working_hours'] != false) return true;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr(context, "Вне рабочего графика")),
          content: Text(
            tr(
              context,
              "Это время вне рабочего графика мастера. Всё равно назначить заказ?",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, "Выбрать другое время")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, "Всё равно назначить")),
            ),
          ],
        ),
      ) ??
      false;
}
