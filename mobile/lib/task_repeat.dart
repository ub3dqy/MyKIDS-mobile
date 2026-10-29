import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'schedule.dart';
import 'task_rewards.dart';

Map<String, dynamic> taskCreateBody(
  Map<String, dynamic> values,
  Map<String, dynamic>? snapshot,
) {
  final body = {...values};
  if (body.remove('reward_type') == 'result') {
    final options = body['reward_options'] as Map<String, dynamic>;
    body['reward'] = rewardTiers(options)
        .map((tier) => tier['coins'] as int)
        .reduce((a, b) => a > b ? a : b);
  } else {
    body['reward_options'] = null;
  }
  final repeating = body.remove('repeat') == true;
  final limited = body.remove('repeat_limited') == true;
  final start = body.remove('repeat_starts_on') as DateTime?;
  final due = body.remove('due_time') as TimeOfDay?;
  final plannedStart = body.remove('planned_start_time') as TimeOfDay?;
  final plannedEnd = body.remove('planned_end_time') as TimeOfDay?;
  if (repeating) {
    final zone = familyClock(snapshot).location;
    tz.TZDateTime at(TimeOfDay time) => tz.TZDateTime(
      zone,
      start!.year,
      start.month,
      start.day,
      time.hour,
      time.minute,
    );
    body['due_at'] = at(due!);
    body['weekdays'] = [...values['weekdays'] as List<int>]..sort();
    if (limited) {
      body['repeat_until'] = dateOnly(body['repeat_until'] as DateTime);
    } else {
      body.remove('repeat_until');
    }
    if (body['plan'] == true) {
      body['planned_start'] = at(plannedStart!);
      body['planned_end'] = at(plannedEnd!);
    }
  } else {
    body.remove('weekdays');
    body.remove('repeat_until');
  }
  final planned = body.remove('plan') == true;
  for (final key in ['planned_start', 'planned_end']) {
    if (planned) {
      body[key] = (body[key] as DateTime).toUtc().toIso8601String();
    } else {
      body.remove(key);
    }
  }
  body['due_at'] = (body['due_at'] as DateTime).toUtc().toIso8601String();
  body['is_required'] = values['is_required'] == 'required';
  if (body['reviewer_id'] == 'parents') body['reviewer_id'] = null;
  for (final key in ['program_id', 'subject_id']) {
    if (body[key] == 'none') body[key] = null;
  }
  if (body['is_required'] == false) body['penalty'] = 0;
  if (body['reminder_minutes'] == -1) body['reminder_minutes'] = null;
  return body;
}

String taskRepeatText(Map<String, dynamic> recurrence) {
  final days = recurrence['weekdays'];
  final list = days is List ? days : null;
  return list == null
      ? ''
      : list.length == 7
      ? 'Повтор: каждый день'
      : 'Повтор: ${list.map((day) => const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][(day as int) - 1]).join(', ')}';
}
