import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar.dart';
import 'event_style.dart';
import 'event_time_rules.dart';
import 'family_action.dart';
import 'form_layout.dart';
import 'input_validation.dart';
import 'repository.dart';
import 'schedule.dart';

class CalendarEditor extends StatefulWidget {
  final Map<String, dynamic> snapshot;
  final tz.TZDateTime day;
  final Map<String, dynamic>? initial;
  final bool single;
  final TimeOfDay? initialStart;
  final Future<dynamic> Function(Map<String, dynamic>)? onSave;
  final FamilyActionAccess? access;
  const CalendarEditor({
    super.key,
    required this.snapshot,
    required this.day,
    this.initial,
    this.single = false,
    this.initialStart,
    this.onSave,
    this.access,
  });
  @override
  State<CalendarEditor> createState() => _CalendarEditorState();
}

class _ActivityDraft {
  final TextEditingController title;
  final String? id;
  TimeOfDay? start, end;
  _ActivityDraft([CalendarActivity? item])
    : id = item?.id,
      title = TextEditingController(text: item?.title ?? ''),
      start = item == null ? null : _parseTime(item.start),
      end = item == null ? null : _parseTime(item.end);
}

TimeOfDay _parseTime(String value) {
  final parts = value.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

String _time(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;

class _CalendarEditorState extends State<CalendarEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, note;
  final activities = <_ActivityDraft>[];
  // Removed rows keep their controller until their field has been unmounted.
  final retired = <_ActivityDraft>[];
  late DateTime date;
  DateTime? startsOn, until;
  late bool startFollowsDate;
  late TimeOfDay start, end;
  late String color;
  late bool repeating;
  late Set<int> weekdays;
  String? error;
  bool checkingTimes = false;
  bool unavailable = false;
  Map<String, dynamic>? saved;
  bool? gradeSubjects;
  late bool remindersEnabled;
  late final TextEditingController reminder;
  final reminderSection = ExpansibleController();

  bool get allowed => !unavailable && (widget.access?.valid ?? true);
  bool get current =>
      mounted && allowed && ModalRoute.of(context)?.isCurrent == true;

  void accessChanged() {
    if (widget.access?.valid == false) unavailable = true;
    if (mounted) setState(() {});
  }

  void closeEditor([Map<String, dynamic>? result]) {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context, allowed ? result : null);
    }
  }

  List<EventLessonTime> get lessonTimes => [
    for (var i = 0; i < activities.length; i++)
      EventLessonTime(
        activities[i].title.text.trim().isEmpty
            ? 'Занятие ${i + 1}'
            : activities[i].title.text.trim(),
        activities[i].start!,
        activities[i].end!,
      ),
  ];

  String? liveTimeWarning() {
    if (activities.any((item) => item.start == null || item.end == null)) {
      return null;
    }
    return lessonTimeProblem(lessonTimes, start, end)?.message;
  }

  void addActivity() {
    if (!current || checkingTimes || saved != null) return;
    TimeOfDay? next = start;
    if (activities.isNotEmpty) {
      final previous = activities.last;
      if (previous.start == null ||
          previous.end == null ||
          _minutes(previous.end!) <= _minutes(previous.start!)) {
        setState(
          () => error = 'Сначала укажите правильное время предыдущего занятия.',
        );
        return;
      }
      next = nextLessonStart(previous.end!);
      if (next == null) {
        setState(
          () => error =
              'После ${_time(previous.end!)} с перерывом 10 минут новое занятие уже не помещается в этот день.',
        );
        return;
      }
    }
    setState(() {
      activities.add(_ActivityDraft()..start = next);
      error = null;
    });
  }

  Future<bool> resolveTimes(LessonTimeProblem problem) async {
    // Apply child decisions on pop, before the parent save can be tapped again.
    // The editor's owner keeps access alive through all closing animations.
    setState(() {
      checkingTimes = true;
      error = null;
    });
    try {
      final expanded = expandedEventTimes(lessonTimes, start, end);
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => FamilyActionDialog<String>(
          access: widget.access,
          allowOffline: true,
          builder: (context, close) => AlertDialog(
            key: const ValueKey('event-time-conflict'),
            scrollable: true,
            title: Text(switch (problem.kind) {
              LessonProblemKind.outside => 'Время не совпадает',
              LessonProblemKind.overlap => 'Занятия пересекаются',
              LessonProblemKind.reversed => 'Проверьте время занятия',
            }),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: spacedFormItems([
                Text(problem.message),
                if (problem.kind == LessonProblemKind.outside) ...[
                  Text(
                    'Событие: ${_time(start)} — ${_time(end)}. Какое время верное?',
                  ),
                  FilledButton(
                    key: const ValueKey('event-use-lesson-times'),
                    onPressed: () => close('event'),
                    child: Text(
                      'Верны занятия\nСобытие: ${_time(expanded.$1)} — ${_time(expanded.$2)}',
                    ),
                  ),
                  OutlinedButton(
                    key: const ValueKey('event-fix-lesson-times'),
                    onPressed: () => close('lessons'),
                    child: const Text('Верно время события\nИсправить занятия'),
                  ),
                ] else
                  FilledButton(
                    key: const ValueKey('event-fix-lesson-times'),
                    onPressed: () => close('lessons'),
                    child: const Text('Исправить время занятий'),
                  ),
                if (problem.kind == LessonProblemKind.overlap)
                  OutlinedButton(
                    key: const ValueKey('event-keep-overlap'),
                    onPressed: () => close('keep'),
                    child: const Text(
                      'Всё введено правильно. Сохранить как есть',
                    ),
                  ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => close(null),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || !current) return false;
      if (choice == 'event') {
        setState(() {
          start = expanded.$1;
          end = expanded.$2;
          error = null;
        });
      } else if (choice == 'lessons') {
        final corrected = await showDialog<List<EventLessonTime>>(
          context: context,
          builder: (_) => _LessonTimesDialog(
            lessons: lessonTimes,
            start: start,
            end: end,
            access: widget.access,
          ),
        );
        if (!current) return false;
        if (corrected != null) {
          setState(() {
            for (var i = 0; i < activities.length; i++) {
              activities[i].start = corrected[i].start;
              activities[i].end = corrected[i].end;
            }
            error = null;
          });
        }
      }
      return choice == 'keep';
    } finally {
      if (mounted) setState(() => checkingTimes = false);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.access?.repository.addListener(accessChanged);
    widget.access?.addListener(accessChanged);
    final row = widget.initial ?? {};
    remindersEnabled =
        widget.initial == null || row['reminder_minutes'] != null;
    reminder = TextEditingController(text: '${row['reminder_minutes'] ?? 30}');
    title = TextEditingController(text: row['title'] as String? ?? '');
    if (row['grade_subjects'] != null) {
      gradeSubjects =
          row['grade_subjects'] == true || row['grade_subjects'] == 1;
    }
    note = TextEditingController(text: row['note'] as String? ?? '');
    color =
        row['color'] as String? ??
        defaultEventColor(row['kind'] as String? ?? 'school');
    date = widget.single || row['date'] == null
        ? widget.day
        : DateTime.parse(row['date'] as String);
    startFollowsDate = row.isEmpty;
    startsOn = row['starts_on'] != null
        ? DateTime.parse(row['starts_on'] as String)
        : row.isEmpty
        ? date
        : null;
    until = row['until'] == null
        ? null
        : DateTime.parse(row['until'] as String);
    repeating = !widget.single && row.isNotEmpty && row['date'] == null;
    weekdays = Set<int>.from(
      row['weekdays'] is String
          ? jsonDecode(row['weekdays'] as String)
          : row['weekdays'] ?? [],
    );
    start = row['start'] == null
        ? widget.initialStart ?? const TimeOfDay(hour: 9, minute: 0)
        : _parseTime(row['start'] as String);
    end = row['end'] == null
        ? TimeOfDay(hour: (start.hour + 1).clamp(0, 23), minute: start.minute)
        : _parseTime(row['end'] as String);
    if (_minutes(end) <= _minutes(start)) {
      end = const TimeOfDay(hour: 23, minute: 59);
    }
    activities.addAll(
      calendarActivities(row['activities']).map(_ActivityDraft.new),
    );
  }

  @override
  void didUpdateWidget(covariant CalendarEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.access, widget.access)) {
      unavailable = true;
      oldWidget.access?.repository.removeListener(accessChanged);
      oldWidget.access?.removeListener(accessChanged);
      widget.access?.repository.addListener(accessChanged);
      widget.access?.addListener(accessChanged);
    }
  }

  @override
  void dispose() {
    widget.access?.repository.removeListener(accessChanged);
    widget.access?.removeListener(accessChanged);
    reminderSection.dispose();
    reminder.dispose();
    title.dispose();
    note.dispose();
    for (final item in [...activities, ...retired]) {
      item.title.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> pickDate(DateTime? value) async {
    if (!current || checkingTimes || saved != null) return null;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => FamilyActionDialog<DateTime>(
        access: widget.access,
        allowOffline: true,
        builder: (_, close) => Navigator(
          onGenerateRoute: (_) => _EventDateRoute(value ?? date, close),
        ),
      ),
    );
    return current ? picked : null;
  }

  Widget timeButton(
    String label,
    TimeOfDay? value,
    void Function(TimeOfDay) apply, {
    Key? key,
    TimeOfDay? pickerInitial,
  }) => OutlinedButton(
    key: key,
    onPressed: () async {
      if (!current || checkingTimes || saved != null) return;
      final picked = await showDialog<TimeOfDay>(
        context: context,
        builder: (_) => _EventTimePicker(
          initial: value ?? pickerInitial ?? start,
          access: widget.access,
        ),
      );
      if (!current || picked == null) return;
      setState(() {
        apply(picked);
        error = liveTimeWarning();
      });
    },
    child: Text('$label: ${value == null ? 'выбрать' : _time(value)}'),
  );

  Future<void> save({bool allowOverlap = false}) async {
    if (!current || checkingTimes || saved != null) return;
    if (!validateAndReveal(form.currentState!)) return;
    final reminderMinutes = int.tryParse(reminder.text.trim());
    if (remindersEnabled &&
        (reminderMinutes == null ||
            reminderMinutes < 0 ||
            reminderMinutes > 10080)) {
      setState(() {
        error = 'Напоминание: укажите от 0 до 10080 минут';
      });
      reminderSection.expand();
      await WidgetsBinding.instance.endOfFrame;
      if (current) validateAndReveal(form.currentState!);
      return;
    }
    String? problem;
    String? problemField;
    if (_minutes(end) <= _minutes(start)) {
      problem = 'Окончание события должно быть позже начала';
      problemField = 'event-end';
    } else if (repeating && weekdays.isEmpty) {
      problem = 'Выберите дни повторения';
      problemField = 'event-weekdays';
    } else if (repeating &&
        startsOn != null &&
        until != null &&
        dateOnly(until!).compareTo(dateOnly(startsOn!)) < 0) {
      problem = 'Конечная дата повторения должна быть не раньше начальной';
      problemField = 'event-until';
    } else if (activities.any(
      (item) => item.start == null || item.end == null,
    )) {
      problem = 'У каждого занятия выберите начало и окончание';
      final i = activities.indexWhere(
        (item) => item.start == null || item.end == null,
      );
      problemField = activities[i].start == null
          ? 'activity-start-$i'
          : 'activity-end-$i';
    } else {
      final conflict = lessonTimeProblem(
        lessonTimes,
        start,
        end,
        allowOverlap: allowOverlap,
      );
      if (conflict != null) {
        final keep = await resolveTimes(conflict);
        if (keep && current) await save(allowOverlap: true);
        return;
      }
    }
    if (problem != null) {
      setState(() => error = problem);
      if (problemField != null) revealNamedField(context, problemField);
      return;
    }
    final original = widget.initial ?? {};
    final ordered = [...activities]
      ..sort((a, b) => _minutes(a.start!).compareTo(_minutes(b.start!)));
    final body = <String, dynamic>{
      'title': title.text.trim(),
      'note': note.text.trim(),
      'start': _time(start),
      'end': _time(end),
      'color': color,
      'activities': [
        for (final item in ordered)
          {
            if (item.id != null) 'id': item.id,
            'title': item.title.text.trim(),
            'start': _time(item.start!),
            'end': _time(item.end!),
          },
      ],
      'allow_overlaps': allowOverlap,
      'grade_subjects':
          gradeSubjects ??
          schoolSubjects({...original, 'title': title.text.trim()}),
      'date': repeating ? null : dateOnly(date),
      'weekdays': repeating ? (weekdays.toList()..sort()) : [],
      'starts_on': repeating && startsOn != null ? dateOnly(startsOn!) : null,
      'until': repeating && until != null ? dateOnly(until!) : null,
      // Preserve existing metadata without exposing extra fields in the simple form.
      'place': original['place'] ?? '',
      'kind': original['kind'] ?? 'other',
      'subject_id': original['subject_id'],
      'reminder_minutes': remindersEnabled ? reminderMinutes : null,
    };
    setState(() => checkingTimes = true);
    try {
      widget.access?.requireCurrent();
      await widget.onSave?.call(body);
      if (!mounted) return;
      setState(() => saved = body);
      if (current) closeEditor(body);
    } catch (failure) {
      if (mounted && allowed) {
        setState(
          () => error = failure is ApiFailure ? failure.message : 'Не удалось сохранить событие. Проверьте соединение и попробуйте ещё раз',
        );
      }
    } finally {
      if (mounted) setState(() => checkingTimes = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: BackButton(onPressed: closeEditor),
      title: Text(
        widget.initial == null ? 'Новое событие' : 'Изменить событие',
      ),
    ),
    body: SafeArea(
      top: false,
      child: !allowed || saved != null
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                children: spacedFormItems([
                  Text(
                    allowed ? 'Событие сохранено' : 'Нужно открыть окно заново',
                  ),
                  Text(
                    allowed
                        ? 'Изменения сохранены. Можно вернуться в календарь.'
                        : 'Семейный доступ изменился. Закройте это окно.',
                  ),
                  FilledButton(
                    onPressed: () => closeEditor(saved),
                    child: const Text('Закрыть'),
                  ),
                ]),
              ),
            )
          : Form(
              key: form,
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: spacedFormItems([
                            LabeledInput(
                              label: 'Название',
                              child: TextFormField(
                                key: const ValueKey('event-title'),
                                controller: title,
                                onChanged: (_) => setState(() {}),
                                maxLength: 200,
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Введите название'
                                    : null,
                              ),
                            ),
                            LabeledInput(
                              label: 'Примечание',
                              child: TextFormField(
                                key: const ValueKey('event-note'),
                                controller: note,
                                maxLength: 4000,
                                minLines: 2,
                                maxLines: 4,
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () async {
                                final picked = await pickDate(date);
                                if (mounted && picked != null) {
                                  setState(() {
                                    if (startFollowsDate) {
                                      startsOn = picked;
                                    }
                                    date = picked;
                                  });
                                }
                              },
                              child: Text('Дата: ${calendarDateLabel(date)}'),
                            ),
                            timeButton(
                              'Начало',
                              start,
                              (value) => start = value,
                              key: const ValueKey('event-start'),
                            ),
                            timeButton(
                              'Окончание',
                              end,
                              (value) => end = value,
                              key: const ValueKey('event-end'),
                            ),
                            const Text(
                              'Цвет события',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final item in eventColors.entries)
                                  ChoiceChip(
                                    key: ValueKey('event-color-${item.key}'),
                                    label: Text(item.value.$1),
                                    selected: color == item.key,
                                    backgroundColor: item.value.$2,
                                    selectedColor: item.value.$2,
                                    side: BorderSide(
                                      color: color == item.key
                                          ? item.value.$3
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                    onSelected: (_) =>
                                        setState(() => color = item.key),
                                  ),
                              ],
                            ),
                            const Text(
                              'Занятия внутри события',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SwitchListTile(
                              title: Text(
                                activities.isEmpty
                                    ? 'Это школьный предмет'
                                    : 'Занятия — школьные предметы',
                              ),
                              subtitle: const Text(
                                'Оценки ставятся за отдельные предметы, а не за всё событие.',
                              ),
                              value:
                                  gradeSubjects ??
                                  schoolSubjects({
                                    ...?widget.initial,
                                    'title': title.text.trim(),
                                  }),
                              onChanged: (value) =>
                                  setState(() => gradeSubjects = value),
                            ),
                            if (activities.isEmpty)
                              const Text(
                                'Например, уроки в школе. Для каждого занятия нужны название и время.',
                              ),
                            for (var i = 0; i < activities.length; i++)
                              Container(
                                key: ObjectKey(activities[i]),
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 12,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: Color(0xffc9d1dd)),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: spacedFormItems([
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text('Занятие ${i + 1}'),
                                        ),
                                        IconButton(
                                          tooltip: 'Удалить занятие ${i + 1}',
                                          onPressed: () => setState(() {
                                            retired.add(activities.removeAt(i));
                                            error = null;
                                          }),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                    LabeledInput(
                                      label: 'Название занятия',
                                      child: TextFormField(
                                        key: ValueKey('activity-title-$i'),
                                        controller: activities[i].title,
                                        maxLength: 200,
                                        validator: (value) =>
                                            value == null ||
                                                value.trim().isEmpty
                                            ? 'Введите название занятия'
                                            : null,
                                      ),
                                    ),
                                    timeButton(
                                      'Начало',
                                      activities[i].start,
                                      (value) => activities[i].start = value,
                                      key: ValueKey('activity-start-$i'),
                                    ),
                                    timeButton(
                                      'Окончание',
                                      activities[i].end,
                                      (value) => activities[i].end = value,
                                      key: ValueKey('activity-end-$i'),
                                      pickerInitial: activities[i].start,
                                    ),
                                  ]),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: activities.length >= 32
                                  ? null
                                  : addActivity,
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить занятие'),
                            ),
                            ExpansionTile(
                              controller: reminderSection,
                              title: const Text('Напоминание'),
                              children: [
                                SwitchListTile(
                                  title: const Text('Напомнить о событии'),
                                  value: remindersEnabled,
                                  onChanged: (value) =>
                                      setState(() => remindersEnabled = value),
                                ),
                                if (remindersEnabled)
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: TextFormField(
                                      key: const ValueKey('event-reminder'),
                                      controller: reminder,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'За сколько минут',
                                        helperText: '0 — в начале события',
                                      ),
                                      validator: (value) {
                                        final minutes = int.tryParse(
                                          value?.trim() ?? '',
                                        );
                                        return minutes == null ||
                                                minutes < 0 ||
                                                minutes > 10080
                                            ? 'Укажите от 0 до 10080 минут'
                                            : null;
                                      },
                                    ),
                                  ),
                              ],
                            ),
                            if (!widget.single)
                              ExpansionTile(
                                title: const Text('Повторение'),
                                initiallyExpanded: repeating,
                                tilePadding: EdgeInsets.zero,
                                children: spacedFormItems([
                                  SwitchListTile(
                                    title: const Text(
                                      'Повторять по дням недели',
                                    ),
                                    value: repeating,
                                    onChanged: (value) =>
                                        setState(() => repeating = value),
                                  ),
                                  if (repeating) ...[
                                    Wrap(
                                      key: const ValueKey('event-weekdays'),
                                      spacing: 6,
                                      runSpacing: 8,
                                      children: [
                                        for (var i = 1; i <= 7; i++)
                                          FilterChip(
                                            label: Text(
                                              calendarWeekdays[i - 1],
                                            ),
                                            selected: weekdays.contains(i),
                                            onSelected: (value) => setState(() {
                                              value
                                                  ? weekdays.add(i)
                                                  : weekdays.remove(i);
                                            }),
                                          ),
                                      ],
                                    ),
                                    for (final first in [true, false])
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          OutlinedButton(
                                            key: ValueKey(
                                              first
                                                  ? 'event-starts-on'
                                                  : 'event-until',
                                            ),
                                            onPressed: () async {
                                              final picked = await pickDate(
                                                first ? startsOn : until,
                                              );
                                              if (!mounted || picked == null) {
                                                return;
                                              }
                                              setState(() {
                                                if (first) {
                                                  startsOn = picked;
                                                  startFollowsDate = false;
                                                } else {
                                                  until = picked;
                                                }
                                              });
                                            },
                                            child: Text(
                                              '${first ? 'С даты' : 'До даты'}: ${(first ? startsOn : until) == null ? 'без ограничения' : dateOnly((first ? startsOn : until)!)}',
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => setState(() {
                                              if (first) {
                                                startsOn = null;
                                                startFollowsDate = false;
                                              } else {
                                                until = null;
                                              }
                                            }),
                                            child: const Text(
                                              'Сбросить ограничение',
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ]),
                              ),
                          ]),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: constraints.maxHeight * .22,
                                ),
                                child: SingleChildScrollView(
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      error!,
                                      style: const TextStyle(
                                        color: Color(0xff942b20),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          FilledButton(
                            key: const ValueKey('event-save'),
                            onPressed: checkingTimes ? null : save,
                            child: const Text('Сохранить'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}

/// The stock date dialog closes its nearest navigator. Keep that decision local
/// so its old buttons cannot pop a route opened over the editor's dialog.
class _EventDateRoute extends MaterialPageRoute<DateTime> {
  final void Function(DateTime?) decide;

  _EventDateRoute(DateTime initial, this.decide)
    : super(
        builder: (_) => DatePickerDialog(
          initialDate: initial,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        ),
      );

  @override
  bool didPop(DateTime? result) {
    addLocalHistoryEntry(LocalHistoryEntry(onRemove: () => decide(result)));
    return super.didPop(result);
  }
}

class _LessonTimesDialog extends StatefulWidget {
  final List<EventLessonTime> lessons;
  final TimeOfDay start, end;
  final FamilyActionAccess? access;
  const _LessonTimesDialog({
    required this.lessons,
    required this.start,
    required this.end,
    this.access,
  });
  @override
  State<_LessonTimesDialog> createState() => _LessonTimesDialogState();
}

class _LessonTimesDialogState extends State<_LessonTimesDialog> {
  late List<EventLessonTime> lessons;
  String? error;
  @override
  void initState() {
    super.initState();
    lessons = [...widget.lessons];
  }

  Future<void> pick(int index, bool start) async {
    if (!mounted ||
        widget.access?.valid == false ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final lesson = lessons[index];
    final value = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => _EventTimePicker(
        initial: start ? lesson.start : lesson.end,
        title: '${lesson.title}: ${start ? 'начало' : 'окончание'}',
        access: widget.access,
      ),
    );
    if (value == null ||
        !mounted ||
        widget.access?.valid == false ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() {
      lessons[index] = start
          ? lesson.copyWith(start: value)
          : lesson.copyWith(end: value);
      error = null;
    });
  }

  @override
  Widget build(
    BuildContext context,
  ) => FamilyActionDialog<List<EventLessonTime>>(
    access: widget.access,
    allowOffline: true,
    builder: (context, close) => AlertDialog(
      key: const ValueKey('lesson-time-correction'),
      title: const Text('Исправить время занятий'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: spacedFormItems([
          Text(
            'Время события: ${_time(widget.start)} — ${_time(widget.end)}. Занятия должны находиться внутри него и не пересекаться.',
          ),
          for (var i = 0; i < lessons.length; i++) ...[
            Text(
              '${i + 1}. ${lessons[i].title}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            OutlinedButton(
              key: ValueKey('correct-activity-start-$i'),
              onPressed: () => pick(i, true),
              child: Text('Начало: ${_time(lessons[i].start)}'),
            ),
            OutlinedButton(
              key: ValueKey('correct-activity-end-$i'),
              onPressed: () => pick(i, false),
              child: Text('Окончание: ${_time(lessons[i].end)}'),
            ),
          ],
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: const TextStyle(color: Color(0xff942b20)),
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => close(null), child: const Text('Отмена')),
        TextButton(
          key: const ValueKey('apply-lesson-times'),
          onPressed: () {
            if (!mounted ||
                widget.access?.valid == false ||
                ModalRoute.of(context)?.isCurrent != true) {
              return;
            }
            final problem = lessonTimeProblem(
              lessons,
              widget.start,
              widget.end,
            );
            if (problem != null) {
              setState(() => error = problem.message);
              return;
            }
            close(lessons);
          },
          child: const Text('Применить'),
        ),
      ],
    ),
  );
}

class _EventTimePicker extends StatefulWidget {
  final TimeOfDay initial;
  final String title;
  final FamilyActionAccess? access;
  const _EventTimePicker({
    required this.initial,
    this.title = 'Выберите время',
    this.access,
  });
  @override
  State<_EventTimePicker> createState() => _EventTimePickerState();
}

class _EventTimePickerState extends State<_EventTimePicker> {
  final form = GlobalKey<FormState>();
  late final TextEditingController hour, minute;
  @override
  void initState() {
    super.initState();
    hour = TextEditingController(text: '${widget.initial.hour}');
    minute = TextEditingController(
      text: widget.initial.minute.toString().padLeft(2, '0'),
    );
  }

  @override
  void dispose() {
    hour.dispose();
    minute.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FamilyActionDialog<TimeOfDay>(
    access: widget.access,
    allowOffline: true,
    builder: (context, close) => AlertDialog(
      key: const ValueKey('event-time-picker'),
      title: Text(widget.title),
      scrollable: true,
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: spacedFormItems([
            for (final hours in [true, false])
              LabeledInput(
                label: hours ? 'Часы' : 'Минуты',
                child: TextFormField(
                  key: ValueKey(hours ? 'time-hour' : 'time-minute'),
                  controller: hours ? hour : minute,
                  keyboardType: TextInputType.number,
                  maxLength: 2,
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null ||
                            number < 0 ||
                            number > (hours ? 23 : 59)
                        ? hours
                              ? 'От 0 до 23'
                              : 'От 0 до 59'
                        : null;
                  },
                ),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => close(null), child: const Text('Отмена')),
        TextButton(
          onPressed: () {
            if (!mounted ||
                widget.access?.valid == false ||
                ModalRoute.of(context)?.isCurrent != true) {
              return;
            }
            if (validateAndReveal(form.currentState!)) {
              close(
                TimeOfDay(
                  hour: int.parse(hour.text),
                  minute: int.parse(minute.text),
                ),
              );
            }
          },
          child: const Text('Готово'),
        ),
      ],
    ),
  );
}
