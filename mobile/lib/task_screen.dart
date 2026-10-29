import 'dart:convert';

import 'design_system.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'activity_lists.dart';
import 'forms.dart';
import 'family_action.dart';
import 'calendar.dart';
import 'form_layout.dart';
import 'input_validation.dart';
import 'child_visuals.dart';
import 'repository.dart';
import 'schedule.dart';
import 'task_rules.dart';
import 'task_repeat.dart';
import 'task_rewards.dart';
import 'task_photo_viewer.dart';
import 'task_summary.dart';
import 'task_submission.dart';
import 'math_answers.dart';
import 'engagement/engagement_entries.dart';
import 'engagement/engagement_scope.dart';

Future<void> openCalendarTasks(
  BuildContext context,
  FamilyRepository repository,
  Future<void> Function(Future<Map<String, dynamic>> Function()) perform,
  DateTime day,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Семейные задания')),
      body: TaskScreen(
        repository: repository,
        perform: perform,
        calendarDay: day,
      ),
    ),
  ),
);

Future<void> openCalendarTask(
  BuildContext context,
  FamilyRepository repository,
  Future<void> Function(Future<Map<String, dynamic>> Function()) perform,
  String taskId,
  DateTime day,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Задание')),
      body: TaskScreen(
        repository: repository,
        perform: perform,
        focusTaskId: taskId,
        calendarDay: day,
      ),
    ),
  ),
);

Future<void> openTaskReview(
  BuildContext context,
  FamilyRepository repository,
  Future<void> Function(Future<Map<String, dynamic>> Function()) perform,
  String taskId,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Проверка задания')),
      body: TaskScreen(
        repository: repository,
        perform: perform,
        reviewTaskId: taskId,
      ),
    ),
  ),
);

class TaskScreen extends StatefulWidget {
  final FamilyRepository repository;
  final Future<void> Function(Future<Map<String, dynamic>> Function()) perform;
  final String? reviewTaskId;
  final String? focusTaskId;
  final DateTime? calendarDay;
  final Future<List<String>> Function(int limit)? selectPhotos;
  const TaskScreen({
    super.key,
    required this.repository,
    required this.perform,
    this.reviewTaskId,
    this.focusTaskId,
    this.calendarDay,
    this.selectPhotos,
  }) : assert(reviewTaskId == null || focusTaskId == null);
  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  FamilyRepository get repo => widget.repository;
  bool onlyReview = false;
  DateTime? repeatDay;
  bool get singleTask =>
      widget.focusTaskId != null || widget.reviewTaskId != null;
  late final FamilyRepository openedRepository;
  late final String openedSession;
  late final int openedGeneration;
  MaterialPageRoute<void>? _photoRoute;
  NavigatorState? _photoNavigator;
  bool _interactionOpen = false;
  FamilyActionAccess? _activeAccess;
  FamilyActionAccess? _submissionViewAccess;

  FamilyActionAccess captureSubmissionAccess() {
    if (_submissionViewAccess == null || !_submissionViewAccess!.valid) {
      _submissionViewAccess?.dispose();
      final owner = repo;
      _submissionViewAccess = FamilyActionAccess(
        owner,
        permitted: () =>
            mounted && identical(repo, owner) && owner.role == 'child',
      );
    }
    return _submissionViewAccess!;
  }

  bool canCreate(FamilyRepository owner) =>
      owner.role == 'parent' ||
      (owner.role == 'relative' &&
          owner.snapshot?['user']?['create_tasks'] == 1);

  bool canEdit(FamilyRepository owner, Map<String, dynamic> task) =>
      canCreate(owner) &&
      (owner.role == 'parent' || task['author_id'] == owner.userId);

  Future<void> interact(
    Future<void> Function(FamilyRepository owner, FamilyActionAccess access)
    action, {
    required bool Function(FamilyRepository) allowed,
  }) async {
    if (_interactionOpen || !mounted) return;
    final owner = repo;
    final access = FamilyActionAccess(
      owner,
      permitted: () => mounted && identical(repo, owner) && allowed(owner),
    );
    if (!access.valid) {
      access.dispose();
      return;
    }
    _interactionOpen = true;
    _activeAccess = access;
    try {
      await action(owner, access);
    } finally {
      _interactionOpen = false;
      _activeAccess = null;
      access.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    openedRepository = repo;
    openedSession = repo.sessionTag;
    openedGeneration = repo.generation;
    repeatDay = widget.calendarDay;
    repo.addListener(refresh);
  }

  void refresh() {
    if (_activeAccess?.valid == false) _activeAccess?.invalidate();
    if (_submissionViewAccess?.valid == false) {
      _submissionViewAccess?.invalidate();
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant TaskScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != repo) {
      _activeAccess?.invalidate();
      _submissionViewAccess?.invalidate();
      _closePhotoViewer();
      oldWidget.repository.removeListener(refresh);
      repo.addListener(refresh);
    }
    if (widget.calendarDay != oldWidget.calendarDay) {
      repeatDay = widget.calendarDay;
    }
  }

  @override
  void dispose() {
    _activeAccess?.invalidate();
    _submissionViewAccess?.dispose();
    _closePhotoViewer();
    repo.removeListener(refresh);
    super.dispose();
  }

  void _closePhotoViewer() {
    final route = _photoRoute;
    final navigator = _photoNavigator;
    _photoRoute = null;
    _photoNavigator = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator != null && navigator.mounted && route?.isActive == true) {
        navigator.removeRoute(route!);
      }
    });
  }

  Future<void> showPhotos(
    List<Future<File> Function()> photos,
    int initialIndex,
  ) async {
    if (!mounted || !repo.signedIn || photos.isEmpty || _photoRoute != null) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final repository = repo;
    final navigator = Navigator.of(context);
    final viewer = TaskPhotoViewer(
      repository: repository,
      photos: photos,
      initialIndex: initialIndex,
    );
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => viewer,
    );
    _photoNavigator = navigator;
    _photoRoute = route;
    try {
      await navigator.push(route);
      await route.completed;
    } finally {
      if (_photoRoute == route) {
        _photoRoute = null;
        _photoNavigator = null;
      }
    }
  }

  Object? validatePlan(Map<String, dynamic> data, [DateTime? deadline]) {
    final reminder = data['reminder_minutes'] as int?;
    if (reminder == null || reminder < -1 || reminder > 10080) {
      return const FieldIssue(
        'reminder_minutes',
        'Напоминание: от −1 до 10080 минут',
      );
    }
    if (data['plan'] == true) {
      final start = data['planned_start'] as DateTime;
      final end = data['planned_end'] as DateTime;
      if (!end.isAfter(start)) {
        return const FieldIssue(
          'planned_end',
          'Окончание должно быть позже начала',
        );
      }
      if (end.isAfter(deadline ?? data['due_at'] as DateTime)) {
        return const FieldIssue(
          'planned_end',
          'Работа должна закончиться до срока задания',
        );
      }
    }
    return null;
  }

  Future<void> createTask([
    Map<String, dynamic>? template,
    bool editing = false,
    bool future = false,
  ]) => interact(
    (owner, access) => _createTask(owner, access, template, editing, future),
    allowed: (owner) =>
        canCreate(owner) &&
        (!editing || template != null && canEdit(owner, template)),
  );

  Future<void> _createTask(
    FamilyRepository owner,
    FamilyActionAccess access, [
    Map<String, dynamic>? template,
    bool editing = false,
    bool future = false,
  ]) async {
    if (!access.valid) return;
    final clock = familyClock(owner.snapshot);
    final selectedDay = !editing && widget.calendarDay != null
        ? repeatDay ?? widget.calendarDay!
        : null;
    // Construct local times on the selected civil date without crossing midnight.
    tz.TZDateTime atSelectedDay(int hour, {int days = 0}) {
      final date = selectedDay!;
      return tz.TZDateTime(
        clock.location,
        date.year,
        date.month,
        date.day + days,
        hour,
      );
    }

    final recurrence = template == null
        ? null
        : repo
              .rows('task_recurrences')
              .where((row) => row['id'] == template['recurrence_id'])
              .firstOrNull;
    final due = editing
        ? familyClock(
            owner.snapshot,
            DateTime.parse(template!['due_at'] as String),
          )
        : selectedDay != null
        ? atSelectedDay(20)
        : clock.add(const Duration(days: 1));
    final firstRepeat = selectedDay != null
        ? atSelectedDay(0)
        : editing && dateOnly(due).compareTo(dateOnly(clock)) >= 0
        ? due
        : clock;
    final reviewerChoices = <String, String>{
      'parents': 'Мама или папа',
      for (final member
          in repo
              .rows('members')
              .where(
                (member) =>
                    member['active'] == 1 &&
                    (member['role'] == 'parent' ||
                        (member['role'] == 'relative' &&
                            member['review_tasks'] == 1)),
              ))
        member['id'] as String: member['name'] as String,
    };
    final previousReviewer = template?['reviewer_id'] as String?;
    final shownReviewers = {
      ...reviewerChoices,
      if (previousReviewer != null &&
          !reviewerChoices.containsKey(previousReviewer))
        previousReviewer: 'Прежний проверяющий недоступен — выберите другого',
    };
    DateTime planned(String key, int hours) => editing && template![key] != null
        ? familyClock(owner.snapshot, DateTime.parse(template[key] as String))
        : selectedDay != null
        ? atSelectedDay(key == 'planned_start' ? 17 : 18)
        : clock.add(Duration(hours: hours));
    final data = await familyForm(
      context,
      editing
          ? (future ? 'Изменить этот и следующие дни' : 'Изменить задание')
          : template == null
          ? 'Новое задание'
          : 'Повторить задание',
      [
        FamilyField('title', 'Название', initial: template?['title']),
        FamilyField(
          'description',
          'Описание',
          kind: 'note',
          required: false,
          initial: template?['description'],
        ),
        FamilyField(
          'repeat',
          'Повторять по дням недели',
          kind: 'bool',
          initial: future,
          visibleWhen: (_) => !editing || future,
          help: 'Каждый день выполняется и проверяется отдельно. Награда и штраф — по условиям задания. Повтор можно остановить.',
        ),
        FamilyField(
          'due_at',
          'Срок выполнения',
          kind: 'datetime',
          initial: due,
          visibleWhen: (values) => values['repeat'] != true,
          help: 'Если задано время в календаре, до этого срока ребёнок может отметить выполнение. Родитель может проверить позже.',
        ),
        FamilyField(
          'weekdays',
          'Дни повторения',
          kind: 'weekdays',
          initial: future && recurrence != null
              ? List<int>.from(jsonDecode(recurrence['weekdays'] as String))
              : <int>[1, 2, 3, 4, 5, 6, 7],
          visibleWhen: (values) => values['repeat'] == true,
        ),
        FamilyField(
          'repeat_starts_on',
          'Начинать с',
          kind: 'date',
          initial: firstRepeat,
          visibleWhen: (values) => values['repeat'] == true,
        ),
        FamilyField(
          'due_time',
          'Выполнить до',
          kind: 'time',
          initial: future
              ? TimeOfDay.fromDateTime(due)
              : const TimeOfDay(hour: 20, minute: 0),
          visibleWhen: (values) => values['repeat'] == true,
          help: 'Если задано время в календаре, это срок отметки ребёнка. Родитель может проверить позже.',
        ),
        FamilyField(
          'repeat_limited',
          'Указать последний день повторения',
          kind: 'bool',
          initial: future && recurrence?['until'] != null,
          visibleWhen: (values) => values['repeat'] == true,
        ),
        FamilyField(
          'repeat_until',
          'Повторять до',
          kind: 'date',
          initial: future && recurrence?['until'] != null
              ? DateTime.parse(recurrence!['until'] as String)
              : selectedDay != null
              ? atSelectedDay(0, days: 30)
              : clock.add(const Duration(days: 30)),
          visibleWhen: (values) =>
              values['repeat'] == true && values['repeat_limited'] == true,
        ),
        FamilyField(
          'plan',
          'Назначить время в календаре',
          kind: 'bool',
          initial: editing && template?['planned_start'] != null,
        ),
        FamilyField(
          'planned_start',
          'Начало работы (если время назначено)',
          kind: 'datetime',
          initial: planned('planned_start', 1),
          visibleWhen: (values) =>
              values['plan'] == true && values['repeat'] != true,
        ),
        FamilyField(
          'planned_end',
          'Окончание работы (если время назначено)',
          kind: 'datetime',
          initial: planned('planned_end', 2),
          visibleWhen: (values) =>
              values['plan'] == true && values['repeat'] != true,
        ),
        FamilyField(
          'planned_start_time',
          'Начало работы',
          kind: 'time',
          initial: editing && template?['planned_start'] != null
              ? TimeOfDay.fromDateTime(planned('planned_start', 1))
              : const TimeOfDay(hour: 17, minute: 0),
          visibleWhen: (values) =>
              values['plan'] == true && values['repeat'] == true,
        ),
        FamilyField(
          'planned_end_time',
          'Окончание работы',
          kind: 'time',
          initial: editing && template?['planned_end'] != null
              ? TimeOfDay.fromDateTime(planned('planned_end', 2))
              : const TimeOfDay(hour: 18, minute: 0),
          visibleWhen: (values) =>
              values['plan'] == true && values['repeat'] == true,
        ),
        FamilyField(
          'reminder_minutes',
          'Напомнить за минут (−1 — не напоминать)',
          kind: 'signed',
          initial: editing ? (template!['reminder_minutes'] ?? -1) : 30,
        ),
        FamilyField(
          'is_required',
          'Тип задания',
          kind: 'choice',
          initial: template == null || taskIsRequired(template)
              ? 'required'
              : 'optional',
          choices: const {
            'required': 'Обязательное',
            'optional': 'Необязательное',
          },
          help: 'Обязательное: штраф за невыполнение. Необязательное: без штрафа. Награда может быть 0. Все начисления подтверждает взрослый.',
        ),
        FamilyField(
          'reward_type',
          'Как начислять награду',
          kind: 'choice',
          initial: template != null && taskRewardOptions(template) != null
              ? 'result'
              : 'fixed',
          choices: const {
            'fixed': 'Одна сумма',
            'result': 'По числу решённых задач',
          },
        ),
        FamilyField(
          'reward',
          'Награда в монетах',
          kind: 'int',
          initial: template?['reward'] ?? 0,
          help: '0 — задание без награды.',
          visibleWhen: (values) => values['reward_type'] == 'fixed',
        ),
        FamilyField(
          'reward_options',
          'Награда по результату',
          kind: 'task_rewards',
          initial: template == null
              ? mathRewardExample()
              : taskRewardOptions(template) ?? mathRewardExample(),
          visibleWhen: (values) => values['reward_type'] == 'result',
        ),
        FamilyField(
          'penalty',
          'Штраф за невыполнение в монетах',
          kind: 'int',
          initial: template?['penalty'] ?? 0,
          visibleWhen: (values) => values['is_required'] == 'required',
          help: 'Списание только после подтверждения взрослого.',
        ),
        FamilyField(
          'subject_id',
          'Предмет, если это домашнее задание',
          kind: 'choice',
          required: false,
          initial: template?['subject_id'] ?? 'none',
          choices: {
            'none': 'Без предмета',
            for (final s in owner.rows('subjects'))
              s['id'] as String: s['name'] as String,
          },
        ),
        FamilyField(
          'program_id',
          'Программа занятий',
          kind: 'choice',
          required: false,
          initial: template?['program_id'] ?? 'none',
          choices: {
            'none': 'Без программы',
            if (template?['program_id'] != null &&
                !repo
                    .rows('programs')
                    .any((p) => p['id'] == template!['program_id']))
              template!['program_id'] as String: 'Назначенная программа',
            for (final p in owner.rows('programs'))
              p['id'] as String: p['title'] as String,
          },
        ),
        FamilyField(
          'reviewer_id',
          'Кто проверит',
          kind: 'choice',
          initial: previousReviewer ?? 'parents',
          choices: shownReviewers,
        ),
        FamilyField(
          'require_photo',
          'Нужна фотография результата',
          kind: 'bool',
          initial: template?['require_photo'] == 1,
        ),
        FamilyField(
          'required_photos',
          'Минимум фотографий результата',
          kind: 'int',
          initial: template?['required_photos'] ?? 1,
          visibleWhen: (values) => values['require_photo'] == true,
          help:
              'От 1 до 5. Если нужно сфотографировать две страницы, укажите 2.',
        ),
      ],
      access: access,
      validate: (values) {
        if (values['reward_type'] == 'fixed' &&
            ((values['reward'] as int? ?? -1) < 0 ||
                (values['reward'] as int? ?? -1) > 1000000)) {
          return const FieldIssue(
            'reward',
            'Укажите награду: от 0 до 1000000 монет',
          );
        }
        if (values['require_photo'] == true &&
            ((values['required_photos'] as int? ?? 0) < 1 ||
                (values['required_photos'] as int? ?? 0) > 5)) {
          return const FieldIssue(
            'required_photos',
            'Укажите минимум: от 1 до 5 фотографий',
          );
        }
        if (!reviewerChoices.containsKey(values['reviewer_id'])) {
          return const FieldIssue(
            'reviewer_id',
            'Выберите доступного проверяющего: маму, папу или участника с правом проверки',
          );
        }
        if (future && values['repeat'] != true) {
          return const FieldIssue(
            'repeat',
            'Для этого и следующих дней оставьте повтор включённым. Один день изменяется отдельно',
          );
        }
        if (values['is_required'] == 'required' &&
            (values['penalty'] as int? ?? 0) <= 0) {
          return const FieldIssue(
            'penalty',
            'Укажите штраф: не менее 1 монеты',
          );
        }
        if (values['repeat'] == true) {
          final start = values['repeat_starts_on'] as DateTime;
          final today = dateOnly(familyClock(owner.snapshot));
          if (dateOnly(start).compareTo(today) < 0) {
            return const FieldIssue(
              'repeat_starts_on',
              'Начните повторение с сегодняшнего дня или будущей даты',
            );
          }
          if (values['repeat_limited'] == true &&
              dateOnly(values['repeat_until'] as DateTime)
                      .compareTo(dateOnly(start)) <
                  0) {
            return const FieldIssue(
              'repeat_until',
              'Последний день должен быть не раньше первого',
            );
          }
          if (values['plan'] == true) {
            int minute(String key) {
              final time = values[key] as TimeOfDay;
              return time.hour * 60 + time.minute;
            }

            if (minute('planned_end_time') <= minute('planned_start_time')) {
              return const FieldIssue(
                'planned_end_time',
                'Окончание должно быть позже начала',
              );
            }
            if (minute('planned_end_time') > minute('due_time')) {
              return const FieldIssue(
                'due_time',
                'Срок задания должен быть не раньше окончания работы',
              );
            }
          }
          return validatePlan({...values, 'plan': false});
        }
        return validatePlan(values);
      },
      onSave: (values) {
        access.requireCurrent();
        final body = taskCreateBody(values, owner.snapshot);
        if (editing) {
          body['task_version'] = template!['version'];
          body['scope'] = future ? 'future' : 'single';
          return owner.mutate(
            '/v1/tasks/${template['id']}',
            body,
            method: 'PUT',
          );
        }
        return owner.mutate('/v1/tasks', body);
      },
    );
    if (data == null) return;
  }

  Future<void> planTask(Map<String, dynamic> task) => interact(
    (owner, access) =>
        _planTask(owner, access, Map<String, dynamic>.from(task)),
    allowed: (owner) => canEdit(owner, task),
  );

  Future<void> _planTask(
    FamilyRepository owner,
    FamilyActionAccess access,
    Map<String, dynamic> task,
  ) async {
    final clock = familyClock(owner.snapshot);
    final form = await familyForm(
      context,
      'Время задания в календаре',
      [
        FamilyField(
          'plan',
          'Назначить время',
          kind: 'bool',
          initial: task['planned_start'] != null,
        ),
        FamilyField(
          'planned_start',
          'Начало работы',
          kind: 'datetime',
          initial: task['planned_start'] == null
              ? clock
              : familyClock(
                  owner.snapshot,
                  DateTime.parse(task['planned_start'] as String),
                ),
        ),
        FamilyField(
          'planned_end',
          'Окончание работы',
          kind: 'datetime',
          initial: task['planned_end'] == null
              ? clock.add(const Duration(hours: 1))
              : familyClock(
                  owner.snapshot,
                  DateTime.parse(task['planned_end'] as String),
                ),
        ),
        FamilyField(
          'reminder_minutes',
          'Напомнить за минут (−1 — не напоминать)',
          kind: 'signed',
          initial: task['reminder_minutes'] ?? -1,
        ),
      ],
      access: access,
      offlineSave: true,
      validate: (data) =>
          validatePlan(data, DateTime.parse(task['due_at'] as String)),
      onSave: (values) {
        access.requireCurrent();
        final body = {...values, 'task_version': task['version']};
        final planned = body.remove('plan') == true;
        for (final key in ['planned_start', 'planned_end']) {
          body[key] = planned
              ? (body[key] as DateTime).toUtc().toIso8601String()
              : null;
        }
        if (body['reminder_minutes'] == -1) body['reminder_minutes'] = null;
        return owner.mutate(
          '/v1/tasks/${task['id']}/plan',
          body,
          method: 'PATCH',
          offlineSubmission: true,
        );
      },
    );
    if (form == null) return;
  }

  Future<void> editTask(Map<String, dynamic> task) => interact(
    (owner, access) =>
        _editTask(owner, access, Map<String, dynamic>.from(task)),
    allowed: (owner) => canEdit(owner, task),
  );

  Future<void> _editTask(
    FamilyRepository owner,
    FamilyActionAccess access,
    Map<String, dynamic> task,
  ) async {
    final recurrence = owner
        .rows('task_recurrences')
        .where((row) => row['id'] == task['recurrence_id'])
        .firstOrNull;
    var future = false;
    if (recurrence?['active'] == 1) {
      final choice = await showFamilyActionDialog<String>(
        context: context,
        builder: (context) => FamilyActionDialog<String>(
          access: access,
          builder: (context, close) => AlertDialog(
            scrollable: true,
            title: const Text('Что изменить?'),
            content: const Text(
              'Проверенные результаты и задания на проверке сохранятся. Награды за прошлые дни не изменятся.',
            ),
            actions: [
              TextButton(
                onPressed: () => close(null),
                child: const Text('Вернуться'),
              ),
              OutlinedButton(
                onPressed: () => close('single'),
                child: const Text('Только этот день'),
              ),
              FilledButton(
                onPressed: () => close('future'),
                child: const Text('Этот и следующие дни'),
              ),
            ],
          ),
        ),
      );
      if (choice == null || !access.valid) return;
      future = choice == 'future';
    }
    await _createTask(owner, access, task, true, future);
  }

  Map<String, dynamic>? currentSubmission(Map<String, dynamic> task) {
    final results =
        repo
            .rows('submissions')
            .where(
              (row) => row['task_id'] == task['id'] && row['accepted'] == 1,
            )
            .toList()
          ..sort((a, b) {
            final received = (b['received_at'] as String).compareTo(
              a['received_at'] as String,
            );
            return received != 0
                ? received
                : (b['id'] as String).compareTo(a['id'] as String);
          });
    return results.firstOrNull;
  }

  Future<void> submit(
    Map<String, dynamic> task, {
    Map<String, dynamic>? supplement,
    required FamilyActionAccess viewAccess,
  }) async {
    if (!mounted ||
        !viewAccess.valid ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final selected = Map<String, dynamic>.from(task);
    final previous = supplement == null
        ? null
        : Map<String, dynamic>.from(supplement);
    await interact((owner, access) async {
      final sourceRoute = ModalRoute.of(context);
      bool current() =>
          mounted && access.valid && sourceRoute?.isCurrent == true;
      final supplementing = previous != null;
      final endpoint =
          '/v1/tasks/${selected['id']}/${supplementing ? 'submission-photos' : 'submissions'}';
      if (supplementing) {
        final pending = await owner.pending();
        if (!mounted || !current()) return;
        if (pending.any(
          (row) => row['path'] == endpoint && row['state'] != 'failed',
        )) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Фотографии уже сохранены для отправки. Дождитесь подключения',
              ),
            ),
          );
          return;
        }
      }
      if (!mounted || !current()) return;
      final draft = TaskSubmissionDraft();
      try {
        final confirmed = await showTaskSubmission(
          context: context,
          access: access,
          draft: draft,
          title: selected['title'] as String,
          existing: supplementing
              ? (jsonDecode(
                  previous['attachment_ids'] as String,
                ) as List).length
              : 0,
          needed: selected['require_photo'] == 1
              ? (selected['required_photos'] as int? ?? 1)
              : 0,
          supplementing: supplementing,
          selectPhotos: widget.selectPhotos,
          showPhotos: showPhotos,
        );
        if (!confirmed || !current()) return;
        await widget.perform(() async {
          access.requireCurrent();
          if (!current()) return <String, dynamic>{};
          // From this point the session-bound durable queue owns the files,
          // including uncertain requests that must be retried after reconnect.
          draft.transferred = true;
          final result = await owner.mutate(
            endpoint,
            {
              'attachment_ids': <String>[],
              'task_version': selected['version'],
              if (supplementing) 'submission_id': previous['id'],
              if (!supplementing) ...{
                'note': draft.note.text,
                'marked_at': DateTime.now().toUtc().toIso8601String(),
              },
            },
            offlineSubmission: true,
            files: draft.photos.toList(growable: false),
          );
          if (mounted &&
              current() &&
              (result['accepted'] == true || result['queued'] == true)) {
            await showFamilyActionDialog<void>(
              context: context,
              builder: (_) => FamilyActionDialog<void>(
                builder: (_, close) => AnimatedBuilder(
                  animation: Listenable.merge([owner, access]),
                  builder: (_, _) => access.valid
                      ? ChildSuccessDialog(
                          title: supplementing
                              ? 'Фотографии добавлены'
                              : 'Отличный шаг!',
                          message: result['queued'] == true
                              ? "${supplementing ? 'Фотографии сохранены' : 'Результат сохранён'} на телефоне. Отправим семье после подключения."
                              : supplementing
                              ? 'Новые фотографии добавлены к результату. Взрослый увидит все страницы.'
                              : 'Результат отправлен семье. Монеты появятся после проверки взрослым.',
                          onClose: () => close(null),
                        )
                      : AlertDialog(
                          scrollable: true,
                          title: const Text('Семейный доступ изменился'),
                          actions: [
                            TextButton(
                              onPressed: () => close(null),
                              child: const Text('Закрыть'),
                            ),
                          ],
                        ),
                ),
              ),
            );
          }
          return result;
        });
      } finally {
        await draft.dispose();
      }
    }, allowed: (owner) => owner.role == 'child');
  }

  Future<void> showSubmissionPhotos(
    Map<String, dynamic> submission,
    int initialIndex,
  ) {
    final repository = repo;
    final ids = (jsonDecode(submission['attachment_ids'] as String) as List)
        .cast<String>();
    return showPhotos(
      ids
          .map(
            (id) =>
                () => repository.attachment(id),
          )
          .toList(growable: false),
      initialIndex,
    );
  }

  List<Widget> submissionContent(
    Map<String, dynamic> task, {
    required bool details,
    bool showPhotos = true,
  }) => [
    for (final result
        in repo
            .rows('submissions')
            .where((row) => row['task_id'] == task['id'])) ...[
      if ((result['note'] as String).isNotEmpty)
        Text(
          'Результат: ${result['note']}',
          maxLines: details ? null : 3,
          overflow: details ? null : TextOverflow.ellipsis,
        ),
      if (details) ...[
        Text(
          'Отмечено: ${familyDateTimeText(repo.snapshot, result['marked_at'] as String)}',
        ),
        Text(
          'Получено: ${familyDateTimeText(repo.snapshot, result['received_at'] as String)}',
        ),
      ],
      if (showPhotos && result['accepted'] == 0)
        const Text('При получении задание уже изменилось'),
      if (showPhotos)
        for (final (index, _)
            in (jsonDecode(result['attachment_ids'] as String) as List).indexed)
          TextButton.icon(
            onPressed: () => showSubmissionPhotos(result, index),
            icon: const Icon(Icons.zoom_in),
            label: Text('Посмотреть фото ${index + 1}'),
          ),
    ],
  ];

  bool currentTaskDecision(
    FamilyRepository owner,
    Map<String, dynamic> shown,
    String action,
  ) {
    final current = owner
        .rows('tasks')
        .where((t) => t['id'] == shown['id'])
        .firstOrNull;
    return current != null &&
        current['version'] == shown['version'] &&
        current['status'] == shown['status'] &&
        (action == 'not_completed'
            ? canMarkTaskNotCompleted(owner.snapshot!['user'], current)
            : current['status'] == 'submitted');
  }

  Future<void> taskAction(Map<String, dynamic> task, String action) {
    final shown = Map<String, dynamic>.from(task);
    final decision = ['approve', 'return', 'not_completed'].contains(action);
    var sending = false;
    return interact(
      (owner, access) => _taskAction(owner, access, shown, action, () {
        access.requireCurrent();
        if (decision && !currentTaskDecision(owner, shown, action)) {
          throw ApiFailure(
            409,
            'Задание уже изменилось. Откройте его повторно',
          );
        }
        // A successful reply changes the task before its form closes. Keep
        // ownership checks active, and check the shown revision on every send.
        sending = true;
      }),
      allowed: (owner) {
        if (decision) {
          return canReviewTask(owner.snapshot!['user'], shown) &&
              (sending || currentTaskDecision(owner, shown, action));
        }
        return switch (action) {
          'stop_repeat' => canEdit(owner, shown),
          'approve_finances' ||
          'cancel' ||
          'reschedule' => owner.role == 'parent',
          _ => false,
        };
      },
    );
  }

  VoidCallback taskDecision(Map<String, dynamic> task, String action) {
    final shown = Map<String, dynamic>.from(task);
    return () => taskAction(shown, action);
  }

  Future<void> _taskAction(
    FamilyRepository owner,
    FamilyActionAccess access,
    Map<String, dynamic> task,
    String action,
    VoidCallback beginMutation,
  ) async {
    if (action == 'approve_finances') {
      if (!await confirmTaskFinances(context, owner, task, access: access) ||
          !access.valid) {
        return;
      }
      await widget.perform(() {
        beginMutation();
        return owner.mutate('/v1/tasks/${task['id']}/actions', {
          'action': 'approve_finances',
          'task_version': task['version'],
          'financial_scope': task['financial_approval_scope'],
        });
      });
      return;
    }
    final data = <String, dynamic>{'action': action};
    if (['cancel', 'reschedule', 'stop_repeat', 'return'].contains(action)) {
      data['task_version'] = task['version'];
    }
    if (action == 'approve') {
      data['task_version'] = task['version'];
      if (taskRewardOptions(task) != null) {
        final count = await chooseTaskResult(context, task, access: access);
        if (count == null || !mounted || !access.valid) return;
        data['completed_count'] = count;
      }
    }
    if (!mounted || !access.valid) return;
    if (action == 'stop_repeat') {
      final confirmed = await showFamilyActionDialog<bool>(
        context: context,
        builder: (context) => FamilyActionDialog<bool>(
          access: access,
          builder: (context, close) => AlertDialog(
            scrollable: true,
            title: const Text('Остановить повторение?'),
            content: const Text(
              'Будущие невыполненные задания этого повтора отменятся. Прошлые результаты и задания на проверке сохранятся.',
            ),
            actions: [
              TextButton(
                onPressed: () => close(null),
                child: const Text('Вернуться'),
              ),
              FilledButton(
                onPressed: () => close(true),
                child: const Text('Остановить повтор'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !access.valid) return;
    }
    if (!mounted || !access.valid) return;
    if (action == 'not_completed') {
      if (!await confirmTaskNotCompleted(context, task, access: access)) return;
      data['task_version'] = task['version'];
    }
    if (!mounted || !access.valid) return;
    if (['return', 'cancel', 'reschedule'].contains(action)) {
      final fields = [
        FamilyField(
          'note',
          action == 'return' ? 'Что нужно исправить' : 'Причина',
          kind: 'note',
          required: action == 'return',
        ),
        if (action == 'reschedule')
          FamilyField(
            'due_at',
            'Новый срок',
            kind: 'datetime',
            initial: familyClock(
              owner.snapshot,
              DateTime.parse(task['due_at'] as String),
            ),
          ),
      ];
      final form = await familyForm(
        context,
        action == 'reschedule'
            ? 'Перенести срок'
            : action == 'return'
            ? 'Вернуть на исправление'
            : 'Отменить задание',
        fields,
        access: access,
        onSave: (values) {
          beginMutation();
          final body = {...data, ...values};
          if (body['due_at'] != null) {
            body['due_at'] = (body['due_at'] as DateTime)
                .toUtc()
                .toIso8601String();
          }
          return owner.mutate('/v1/tasks/${task['id']}/actions', body);
        },
      );
      if (form == null) return;
      return;
    }
    await widget.perform(() {
      beginMutation();
      return owner.mutate('/v1/tasks/${task['id']}/actions', data);
    });
  }

  @override
  Widget build(BuildContext context) {
    final submissionAccess = captureSubmissionAccess();
    if ((widget.focusTaskId != null || widget.calendarDay != null) &&
        (!identical(repo, openedRepository) ||
            repo.snapshot == null ||
            !repo.signedIn ||
            repo.sessionTag != openedSession ||
            repo.generation != openedGeneration)) {
      return const Center(
        child: Text('Задания больше недоступны. Вернитесь в календарь.'),
      );
    }
    final selected = repeatDay ?? familyClock(repo.snapshot);
    // Date controls select a civil date, independent of the device timezone.
    final selectedDay = tz.TZDateTime(
      familyClock(repo.snapshot).location,
      selected.year,
      selected.month,
      selected.day,
    );
    final calendarTaskIds = widget.calendarDay != null && !singleTask
        ? calendarDay(repo.snapshot!, selectedDay)
              .where((entry) => entry.key.startsWith('task:'))
              .map((entry) => entry.source!['id'])
              .toSet()
        : null;
    final mayCreate =
        repo.role == 'parent' ||
        (repo.role == 'relative' &&
            repo.snapshot!['user']['create_tasks'] == 1);
    final tasks =
        repo
            .rows('tasks')
            .where((task) => task['status'] != 'cancelled')
            .where(
              (task) =>
                  calendarTaskIds == null ||
                  calendarTaskIds.contains(task['id']),
            )
            .where(
              (task) =>
                  widget.focusTaskId == null ||
                  task['id'] == widget.focusTaskId,
            )
            .where(
              (task) =>
                  widget.reviewTaskId == null ||
                  (task['id'] == widget.reviewTaskId &&
                      canReviewTask(repo.snapshot!['user'], task)),
            )
            .where(
              (task) =>
                  task['recurrence_id'] == null ||
                  calendarTaskIds != null ||
                  singleTask ||
                  onlyReview ||
                  dateOnly(
                        familyClock(
                          repo.snapshot,
                          DateTime.parse(task['due_at'] as String),
                        ),
                      ) ==
                      dateOnly(repeatDay ?? familyClock(repo.snapshot)),
            )
            .where(
              (t) =>
                  !onlyReview ||
                  t['status'] == 'submitted' ||
                  (t['financial_approved'] == 0 &&
                      [
                        'assigned',
                        'returned',
                        'submitted',
                      ].contains(t['status'])) ||
                  canMarkTaskNotCompleted(repo.snapshot!['user'], t),
            )
            .toList()
          ..sort(compareTaskTime);
    final recurrences = {
      for (final row in repo.rows('task_recurrences'))
        row['id']: {...row, 'weekdays': jsonDecode(row['weekdays'] as String)},
    };
    final programs = repo.rows('programs');
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      children: spacedFormItems([
        if (!singleTask && EngagementScope.maybeOf(context) != null)
          const AdventureEntry(),
        if (repo.role == 'child' && !singleTask)
          gameDesign.value != null
              ? const GameScene(
                  title: 'Мои задания',
                  description: 'Маленькие дела. Большие победы.',
                  compact: true,
                )
              : Text(
                  'Твои задания',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
        if (widget.focusTaskId != null && widget.calendarDay != null)
          Text(
            calendarDateLabel(selectedDay),
            key: const ValueKey('calendar-task-date'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (mayCreate && !singleTask) ...[
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => createTask(),
                  child: const Text('Добавить задание'),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Другие действия с заданиями',
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'program',
                    child: Text('Создать программу из заданий'),
                  ),
                ],
                onSelected: (_) => interact((owner, access) async {
                  await familyForm(
                    context,
                    'Программа занятий',
                    [
                      const FamilyField('title', 'Название'),
                      const FamilyField(
                        'description',
                        'Описание',
                        kind: 'note',
                        required: false,
                      ),
                    ],
                    access: access,
                    onSave: (values) {
                      access.requireCurrent();
                      return owner.mutate('/v1/programs', values);
                    },
                  );
                }, allowed: canCreate),
              ),
            ],
          ),
        ],
        if (repo.role != 'child' && !singleTask)
          SwitchListTile(
            title: const Text('Ждут внимания'),
            value: onlyReview,
            onChanged: (value) => setState(() => onlyReview = value),
          ),
        if (!singleTask &&
            (widget.calendarDay != null ||
                (recurrences.isNotEmpty && !onlyReview))) ...[
          const Text('День заданий'),
          Row(
            children: [
              IconButton(
                tooltip: 'Предыдущий день задания',
                onPressed: () => setState(() {
                  final day = repeatDay ?? familyClock(repo.snapshot);
                  repeatDay = DateTime(day.year, day.month, day.day - 1);
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: repeatDay ?? familyClock(repo.snapshot),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100, 12, 31),
                    );
                    if (picked != null && mounted) {
                      setState(() => repeatDay = picked);
                    }
                  },
                  child: Text(
                    calendarDateLabel(repeatDay ?? familyClock(repo.snapshot)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Следующий день задания',
                onPressed: () => setState(() {
                  final day = repeatDay ?? familyClock(repo.snapshot);
                  repeatDay = DateTime(day.year, day.month, day.day + 1);
                }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
        if (widget.reviewTaskId != null && tasks.isEmpty)
          const Text('Задание больше недоступно для проверки.'),
        if (widget.focusTaskId != null && tasks.isEmpty)
          const Text('Задание отменено или больше недоступно.'),
        if (widget.calendarDay != null && !singleTask && tasks.isEmpty)
          const Text('На выбранную дату заданий нет.'),
        for (final task in tasks)
          ChildSurface(
            key: ValueKey('task-${task['id']}'),
            enabled: repo.role == 'child',
            child: TaskCompactCard(
              key: ValueKey(
                '${repo.sessionTag}:${repo.generation}:${task['id']}',
              ),
              snapshot: repo.snapshot,
              task: task,
              main: [
                if (widget.reviewTaskId == null &&
                    task['status'] == 'submitted' &&
                    canReviewTask(repo.snapshot!['user'], task))
                  FilledButton.icon(
                    key: ValueKey('review-task-${task['id']}'),
                    onPressed: () => openTaskReview(
                      context,
                      repo,
                      widget.perform,
                      task['id'] as String,
                    ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Проверить результат'),
                  ),
                if (repo.role == 'child' &&
                    ['assigned', 'returned'].contains(task['status']))
                  FilledButton(
                    onPressed: () => submit(task, viewAccess: submissionAccess),
                    child: const Text('Готово — отправить на проверку'),
                  ),
                if (repo.role == 'child' &&
                    task['status'] == 'submitted' &&
                    currentSubmission(task) != null)
                  OutlinedButton.icon(
                    onPressed: () => submit(
                      task,
                      supplement: currentSubmission(task),
                      viewAccess: submissionAccess,
                    ),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Добавить фото к результату'),
                  ),
                if (widget.reviewTaskId != null) ...[
                  if (repo.role == 'parent')
                    OutlinedButton.icon(
                      key: ValueKey('math-answers-${task['id']}'),
                      onPressed: () =>
                          openMathAnswers(context, repo, task['id'] as String),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Ответы по математике'),
                    ),
                  ...submissionContent(task, details: false),
                  if (task['status'] == 'submitted' &&
                      canReviewTask(repo.snapshot!['user'], task))
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: taskDecision(task, 'approve'),
                          child: const Text('Подтвердить выполнение'),
                        ),
                        OutlinedButton(
                          onPressed: taskDecision(task, 'return'),
                          child: const Text('Нужно исправить'),
                        ),
                      ],
                    ),
                ],
                if (canMarkTaskNotCompleted(repo.snapshot!['user'], task) &&
                    !(taskIsRequired(task) && task['financial_approved'] == 0))
                  OutlinedButton(
                    key: ValueKey('task-not-completed-${task['id']}'),
                    onPressed: taskDecision(task, 'not_completed'),
                    child: Text(
                      taskIsRequired(task)
                          ? 'Не выполнено — назначить штраф'
                          : 'Закрыть без выполнения',
                    ),
                  ),
              ],
              details: [
                if ((task['description'] as String).isNotEmpty)
                  Text(task['description'] as String),
                Text(taskKindText(task)),
                Text(
                  '${task['planned_end'] == null ? 'Срок выполнения' : 'Отметить в приложении до'}: ${familyDateTimeText(repo.snapshot, task['due_at'] as String)}',
                ),
                Text(taskTermsText(task)),
                Text(taskReviewerText(task, repo.rows('members'))),
                if (mayCreate &&
                    (repo.role == 'parent' ||
                        task['author_id'] == repo.userId) &&
                    ['assigned', 'returned'].contains(task['status']))
                  OutlinedButton(
                    onPressed: () => editTask(task),
                    child: const Text('Редактировать задание'),
                  ),
                if (recurrences[task['recurrence_id']]
                    case final recurrence?) ...[
                  Text(taskRepeatText(recurrence)),
                  if (recurrence['active'] == 0)
                    const Text('Повторение остановлено'),
                  if (recurrence['active'] == 1 &&
                      mayCreate &&
                      (repo.role == 'parent' ||
                          task['author_id'] == repo.userId))
                    TextButton(
                      onPressed: () => taskAction(task, 'stop_repeat'),
                      child: const Text('Остановить повторение'),
                    ),
                ],
                if (task['financial_approved'] == 0 &&
                    [
                      'assigned',
                      'returned',
                      'submitted',
                    ].contains(task['status']))
                  const Text('Суммы ожидают согласования родителем'),
                if ((task['note'] as String).isNotEmpty)
                  Text(task['note'] as String),
                ...submissionContent(
                  task,
                  details: true,
                  showPhotos: widget.reviewTaskId == null,
                ),
                if (widget.reviewTaskId == null &&
                    task['status'] == 'submitted' &&
                    canReviewTask(repo.snapshot!['user'], task))
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: taskDecision(task, 'approve'),
                        child: const Text('Подтвердить выполнение'),
                      ),
                      OutlinedButton(
                        onPressed: taskDecision(task, 'return'),
                        child: const Text('Нужно исправить'),
                      ),
                    ],
                  ),
                if (repo.role == 'parent' &&
                    task['financial_approved'] == 0 &&
                    [
                      'assigned',
                      'returned',
                      'submitted',
                    ].contains(task['status']))
                  FilledButton(
                    onPressed: () => taskAction(task, 'approve_finances'),
                    child: Text(
                      taskIsRequired(task)
                          ? 'Согласовать награду и штраф'
                          : 'Согласовать награду',
                    ),
                  ),
                if (canMarkTaskNotCompleted(repo.snapshot!['user'], task) &&
                    taskIsRequired(task) &&
                    task['financial_approved'] == 0)
                  const OutlinedButton(
                    onPressed: null,
                    child: Text('Не выполнено — назначить штраф'),
                  ),
                if (repo.role == 'parent' &&
                    ![
                      'completed',
                      'cancelled',
                      'not_completed',
                    ].contains(task['status']))
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => taskAction(task, 'reschedule'),
                        child: const Text('Перенести'),
                      ),
                      TextButton(
                        onPressed: () => taskAction(task, 'cancel'),
                        child: const Text('Отменить'),
                      ),
                    ],
                  ),
                if (mayCreate &&
                    (repo.role == 'parent' ||
                        task['author_id'] == repo.userId) &&
                    ['assigned', 'returned'].contains(task['status']))
                  TextButton(
                    onPressed: () => planTask(task),
                    child: const Text('Время в календаре'),
                  ),
                if (mayCreate)
                  TextButton(
                    onPressed: () => createTask(task),
                    child: const Text('Использовать как шаблон'),
                  ),
              ],
            ),
          ),
        if (tasks.isEmpty && !singleTask)
          repo.role == 'child'
              ? const ChildHeader(
                  art: 1,
                  title: 'Пока можно отдохнуть',
                  message: 'Заданий пока нет. Когда семья добавит новое, оно появится здесь.',
                )
              : const Text('Заданий пока нет'),
        if (programs.isNotEmpty && !singleTask)
          ActivityWindow(
            key: const ValueKey('task-programs'),
            count: programs.length,
            filterKey: (repo.sessionTag, repo.generation),
            compactWhenShort: true,
            showCount: false,
            emptyText: '',
            itemBuilder: (_, index) {
              final program = programs[index];
              return ExpansionTile(
                key: ValueKey('program-${program['id']}'),
                title: Text(program['title'] as String),
                subtitle: const Text('Программа заданий'),
                children: [Text(program['description'] as String? ?? '')],
              );
            },
          ),
      ]),
    );
  }
}
