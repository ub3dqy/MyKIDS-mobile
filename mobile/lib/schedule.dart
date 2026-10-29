import 'dart:convert';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _zonesReady = false;
String familyDateTimeText(Map<String, dynamic>? snapshot, String value) {
  final time = familyClock(snapshot, DateTime.parse(value));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.day)}.${two(time.month)}.${time.year} ${two(time.hour)}:${two(time.minute)}';
}

String? taskCalendarTimeText(
  Map<String, dynamic>? snapshot,
  Map<String, dynamic> task,
) {
  final start = task['planned_start'] as String?;
  final end = task['planned_end'] as String?;
  if (start == null || end == null) return null;
  final startClock = familyClock(snapshot, DateTime.parse(start));
  final endClock = familyClock(snapshot, DateTime.parse(end));
  final startText = familyDateTimeText(snapshot, start);
  final endText = dateOnly(startClock) == dateOnly(endClock)
      ? '${endClock.hour.toString().padLeft(2, '0')}:${endClock.minute.toString().padLeft(2, '0')}'
      : familyDateTimeText(snapshot, end);
  return 'В календаре: $startText – $endText';
}

int compareTaskTime(Map<String, dynamic> a, Map<String, dynamic> b) =>
    DateTime.parse(
      a['planned_start'] as String? ?? a['due_at'] as String,
    ).compareTo(
      DateTime.parse(b['planned_start'] as String? ?? b['due_at'] as String),
    );

bool taskIsForToday(
  Map<String, dynamic>? snapshot,
  Map<String, dynamic> task, {
  DateTime? now,
}) {
  final clock = familyClock(snapshot, now);
  final day = familyClock(
    snapshot,
    DateTime.parse(
      task['planned_start'] as String? ?? task['due_at'] as String,
    ),
  );
  final todayDate = dateOnly(clock), taskDate = dateOnly(day);
  return taskDate == todayDate ||
      (taskDate.compareTo(todayDate) < 0 &&
          ['assigned', 'returned', 'submitted'].contains(task['status']));
}

tz.TZDateTime familyClock(Map<String, dynamic>? snapshot, [DateTime? instant]) {
  if (!_zonesReady) {
    tzdata.initializeTimeZones();
    _zonesReady = true;
  }
  final name = snapshot?['family']?['timezone'] as String? ?? 'Europe/Moscow';
  return tz.TZDateTime.from(instant ?? DateTime.now(), tz.getLocation(name));
}

List<Map<String, dynamic>> daySchedule(
  List<Map<String, dynamic>> schedules,
  List<Map<String, dynamic>> exceptions,
  DateTime day,
) {
  final date =
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  final result = <Map<String, dynamic>>[];
  for (final schedule in schedules) {
    if (schedule['active'] == 0 ||
        (schedule['starts_on'] != null &&
            date.compareTo(schedule['starts_on'] as String) < 0) ||
        (schedule['until'] != null &&
            date.compareTo(schedule['until'] as String) > 0)) {
      continue;
    }
    final weekdays = jsonDecode(schedule['weekdays'] as String) as List;
    if (schedule['date'] != date &&
        !(schedule['date'] == null && weekdays.contains(day.weekday))) {
      continue;
    }
    final changes = exceptions.where(
      (e) => e['schedule_id'] == schedule['id'] && e['date'] == date,
    );
    if (changes.isNotEmpty) {
      final replacement = changes.first['replacement'];
      if (replacement == null) continue;
      result.add({
        ...schedule,
        ...Map<String, dynamic>.from(jsonDecode(replacement as String) as Map),
      });
    } else {
      result.add(schedule);
    }
  }
  result.sort((a, b) => (a['start'] as String).compareTo(b['start'] as String));
  return result;
}

String dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String statusText(String? status) =>
    const {
      'assigned': 'Выдано',
      'submitted': 'На проверке',
      'completed': 'Выполнено',
      'not_completed': 'Не выполнено',
      'returned': 'Нужно исправить',
      'cancelled': 'Отменено',
      'pending': 'Ожидает',
      'claimed': 'Родитель готовит выдачу',
      'confirmed': 'Выдано',
      'rejected': 'Отклонено',
      'applied': 'Применён',
      'waived': 'Отменён',
      'ringing': 'Вызов',
      'active': 'Идёт разговор',
      'ended': 'Завершён',
      'invited': 'Приглашён',
      'joined': 'Подключён',
      'declined': 'Отклонён',
      'left': 'Вышел',
      'missed': 'Пропущен',
    }[status] ??
    status ??
    '';

String historyText(String action) =>
    const {
      'task.created': 'Создано задание',
      'task.edited': 'Изменено задание',
      'task.repeat_created': 'Создано повторяющееся задание',
      'task.repeat_edited': 'Изменено повторяющееся задание',
      'task.repeat_stopped': 'Остановлен повтор задания',
      'task.not_completed': 'Подтверждено невыполнение задания',
      'task.submitted': 'Отправлен результат задания',
      'task.approve': 'Задание выполнено и проверено',
      'task.complete': 'Выполнение задания подтверждено в календаре',
      'task.return': 'Задание возвращено для исправления',
      'task.cancel': 'Задание отменено',
      'task.reschedule': 'Срок задания перенесён',
      'task.planned': 'Изменено время задания в календаре',
      'task.waive_penalty': 'Штраф за задание отменён',
      'task.approve_finances': 'Поощрение за задание согласовано',
      'grade.saved': 'Сохранена оценка',
      'grade.deleted': 'Удалена ошибочная оценка',
      'grade.rules': 'Изменены поощрения за оценки',
      'penalty.applied': 'Подтверждён штраф',
      'penalty.waived': 'Штраф отменён',
      'redemption.created': 'Запрошена награда или выдача денег',
      'redemption.claim': 'Родитель взял заявку на выдачу',
      'redemption.confirm': 'Выдача подтверждена',
      'redemption.cancel': 'Заявка отменена',
      'redemption.reject': 'Заявка отклонена',
      'redemption.release': 'Заявка возвращена для выдачи другим родителем',
      'invite.created': 'Создано приглашение в семью',
      'member.permissions': 'Изменён доступ родственника',
      'family.settings': 'Изменены семейные настройки',
      'subject.created': 'Добавлен предмет',
      'schedule.saved': 'Сохранено занятие',
      'schedule.exception': 'Изменено отдельное занятие',
      'schedule.archived': 'Событие убрано из календаря',
      'program.created': 'Создана программа заданий',
      'reward.saved': 'Сохранена награда',
      'call.started': 'Начат семейный звонок',
    }[action] ??
    'Семейное действие';
