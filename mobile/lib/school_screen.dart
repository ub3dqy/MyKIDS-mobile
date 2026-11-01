import 'dart:convert';

import 'package:flutter/material.dart';

import 'calendar.dart';
import 'calendar_results.dart';
import 'event_style.dart';
import 'family_action.dart';
import 'forms.dart';
import 'form_layout.dart';
import 'repository.dart';
import 'schedule.dart';
import 'task_rules.dart';
import 'task_screen.dart';
import 'task_rewards.dart';
import 'design_system.dart';

class SchoolScreen extends StatefulWidget {
  final FamilyRepository repository;
  final bool gradesOnly;
  final DateTime? initialDay;
  final Future<void> Function(Future<Map<String, dynamic>> Function()) perform;
  const SchoolScreen({
    super.key,
    this.gradesOnly = false,
    this.initialDay,
    required this.repository,
    required this.perform,
  });
  @override
  State<SchoolScreen> createState() => _SchoolScreenState();
}

enum _SchoolTaskAction { complete, approveFinances, notCompleted, submit }

class _SchoolScreenState extends State<SchoolScreen> {
  late DateTime day;
  bool busy = false;
  bool gradeAction = false;
  bool _taskInteractionOpen = false;
  FamilyActionAccess? _taskViewAccess, _activeTaskAccess;
  FamilyRepository get repo => widget.repository;
  Map<String, String> get subjects => {
    for (final subject in repo.rows('subjects'))
      subject['id'] as String: subject['name'] as String,
  };

  @override
  void initState() {
    super.initState();
    final date = widget.initialDay ?? familyClock(repo.snapshot);
    day = DateTime(date.year, date.month, date.day);
    repo.addListener(observeTaskAccess);
  }

  void observeTaskAccess() {
    if (_taskViewAccess?.valid == false) _taskViewAccess?.invalidate();
    if (_activeTaskAccess?.valid == false) _activeTaskAccess?.invalidate();
  }

  @override
  void didUpdateWidget(covariant SchoolScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, repo)) {
      oldWidget.repository.removeListener(observeTaskAccess);
      _taskViewAccess?.invalidate();
      _activeTaskAccess?.invalidate();
      repo.addListener(observeTaskAccess);
    }
  }

  @override
  void dispose() {
    repo.removeListener(observeTaskAccess);
    _taskViewAccess?.dispose();
    _activeTaskAccess?.invalidate();
    super.dispose();
  }

  FamilyActionAccess captureTaskViewAccess() {
    final owner = repo;
    if (_taskViewAccess == null || !_taskViewAccess!.valid) {
      _taskViewAccess?.dispose();
      _taskViewAccess = FamilyActionAccess(
        owner,
        permitted: () => mounted && identical(repo, owner),
      );
    }
    return _taskViewAccess!;
  }

  bool taskViewCurrent(FamilyActionAccess view, DateTime selectedDay) =>
      mounted &&
      view.valid &&
      identical(repo, view.repository) &&
      day == selectedDay &&
      ModalRoute.of(context)?.isCurrent == true;

  bool taskDecisionCurrent(
    FamilyRepository owner,
    Map<String, dynamic> shown,
    _SchoolTaskAction action,
  ) {
    final current = owner
        .rows('tasks')
        .where((t) => t['id'] == shown['id'])
        .firstOrNull;
    if (current == null ||
        const [
          'version',
          'status',
          'title',
          'reward',
          'penalty',
          'is_required',
          'reward_options',
          'require_photo',
          'required_photos',
          'financial_approved',
          'financial_approval_scope',
          'author_id',
          'reviewer_id',
          'planned_start',
          'planned_end',
          'due_at',
        ].any((key) => jsonEncode(current[key]) != jsonEncode(shown[key]))) {
      return false;
    }
    final active = [
      'assigned',
      'returned',
      'submitted',
    ].contains(current['status']);
    final approved = current['financial_approved'] == 1;
    return switch (action) {
      _SchoolTaskAction.submit =>
        owner.role == 'child' &&
            ['assigned', 'returned'].contains(current['status']) &&
            current['require_photo'] != 1,
      _SchoolTaskAction.complete =>
        owner.online &&
            active &&
            approved &&
            canReviewTask(owner.snapshot!['user'], current) &&
            (current['require_photo'] != 1 || current['status'] == 'submitted'),
      _SchoolTaskAction.approveFinances =>
        owner.online && active && owner.role == 'parent' && !approved,
      _SchoolTaskAction.notCompleted =>
        owner.online &&
            canMarkTaskNotCompleted(owner.snapshot!['user'], current) &&
            (!taskIsRequired(current) || approved),
    };
  }

  Future<void> taskAction(
    Map<String, dynamic> task,
    _SchoolTaskAction action,
    FamilyActionAccess view,
    DateTime selectedDay,
  ) async {
    if (busy ||
        gradeAction ||
        _taskInteractionOpen ||
        !taskViewCurrent(view, selectedDay)) {
      return;
    }
    final owner = view.repository;
    // Reward tiers are nested JSON. Do not retain a live snapshot inside a decision.
    final shown = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(task)) as Map,
    );
    var sending = false;
    final access = FamilyActionAccess(
      owner,
      permitted: () =>
          mounted &&
          identical(repo, owner) &&
          view.valid &&
          day == selectedDay &&
          (sending || taskDecisionCurrent(owner, shown, action)),
    );
    if (!access.valid) {
      access.dispose();
      return;
    }
    setState(() => _taskInteractionOpen = true);
    _activeTaskAccess = access;
    try {
      final Map<String, dynamic> body;
      if (action == _SchoolTaskAction.complete) {
        body = calendarCompletion(shown, selectedDay);
        if (taskRewardOptions(shown) != null) {
          final count = await chooseTaskResult(context, shown, access: access);
          if (count == null || !access.valid) return;
          body['completed_count'] = count;
        } else {
          final confirmed = await showFamilyActionDialog<bool>(
            context: context,
            builder: (_) => FamilyActionDialog<bool>(
              access: access,
              builder: (context, close) => AlertDialog(
                title: const Text('Подтвердить выполнение?'),
                scrollable: true,
                content: Text(
                  '${shown['title']}\nНаграда: ${shown['reward']} монет.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => close(null),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () => close(true),
                    child: const Text('Выполнено'),
                  ),
                ],
              ),
            ),
          );
          if (confirmed != true || !access.valid) return;
        }
      } else if (action == _SchoolTaskAction.approveFinances) {
        if (!await confirmTaskFinances(context, owner, shown, access: access) ||
            !access.valid) {
          return;
        }
        body = {
          'action': 'approve_finances',
          'task_version': shown['version'],
          'financial_scope': shown['financial_approval_scope'],
        };
      } else if (action == _SchoolTaskAction.notCompleted) {
        if (!await confirmTaskNotCompleted(context, shown, access: access) ||
            !access.valid) {
          return;
        }
        body = {'action': 'not_completed', 'task_version': shown['version']};
      } else {
        body = calendarSubmission(shown);
      }
      if (!taskViewCurrent(view, selectedDay) || !access.valid) return;
      await run(() async {
        access.requireCurrent();
        final submission = action == _SchoolTaskAction.submit;
        final path =
            '/v1/tasks/${shown['id']}/${submission ? 'submissions' : 'actions'}';
        if (submission) {
          final queued = await owner.pending();
          access.requireCurrent();
          if (queued.any(
            (row) => row['path'] == path && row['state'] != 'failed',
          )) {
            throw ApiFailure(
              409,
              'Результат уже сохранён для отправки. Дождитесь подключения.',
            );
          }
        }
        if (sending ||
            !taskViewCurrent(view, selectedDay) ||
            !taskDecisionCurrent(owner, shown, action)) {
          throw ApiFailure(
            409,
            'Задание или доступ изменились. Откройте действие заново.',
          );
        }
        sending = true;
        return owner.mutate(path, body, offlineSubmission: submission);
      });
    } finally {
      _activeTaskAccess = null;
      access.dispose();
      if (mounted) setState(() => _taskInteractionOpen = false);
    }
  }

  Future<void> run(Future<Map<String, dynamic>> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.perform(action);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveGrade(
    CalendarResultItem? item, [
    Map<String, dynamic>? grade,
  ]) async {
    if (busy || gradeAction || !repo.online || repo.role != 'parent') return;
    final owner = repo;
    final identity = (
      owner.endpoint,
      owner.sessionTag,
      owner.generation,
      owner.userId,
    );
    bool owns() =>
        mounted &&
        identical(repo, owner) &&
        owner.signedIn &&
        owner.role == 'parent' &&
        (owner.endpoint, owner.sessionTag, owner.generation, owner.userId) ==
            identity;
    if (!owns()) return;
    grade = grade == null ? null : Map<String, dynamic>.from(grade);
    final selectedDay = day;
    setState(() => gradeAction = true);
    try {
      await familyForm(
        context,
        '${grade == null ? 'Оценка' : 'Исправить оценку'}: ${item?.title ?? gradeTitle(grade!, subjects)}',
        [
          FamilyField(
            'grade',
            'Оценка',
            kind: 'choice',
            choices: const {'5': '5', '4': '4', '3': '3', '2': '2'},
            initial: grade?['grade'].toString(),
          ),
          FamilyField(
            'note',
            'Примечание',
            kind: 'note',
            required: false,
            initial: grade?['note'],
          ),
        ],
        onSave: (values) async {
          if (!owns()) {
            throw ApiFailure(
              401,
              'Семейный доступ изменился. Закройте окно и откройте оценку заново.',
            );
          }
          final body = {
            ...values,
            'date': grade?['date'] ?? dateOnly(selectedDay),
            'grade': int.parse(values['grade'] as String),
          };
          if (grade != null) {
            if (grade['revision'] is String) {
              body['expected_revision'] = grade['revision'];
            }
            if (grade['schedule_id'] != null) {
              body['schedule_id'] = grade['schedule_id'];
              body['activity_id'] = grade['activity_id'];
            } else {
              body['subject_id'] = grade['subject_id'];
            }
          } else {
            body.addAll(item!.gradeSource);
          }
          return owner.mutate(
            '/v1/grades${grade == null ? '' : '/${grade['id']}'}',
            body,
            method: grade == null ? 'POST' : 'PUT',
          );
        },
      );
    } finally {
      if (mounted) setState(() => gradeAction = false);
    }
  }

  Future<void> deleteGrade(Map<String, dynamic> grade) async {
    if (busy || gradeAction || !repo.online || repo.role != 'parent') return;
    final owner = repo;
    final shown = Map<String, dynamic>.from(grade);
    final identity = (
      owner.endpoint,
      owner.sessionTag,
      owner.generation,
      owner.userId,
    );
    var invalidated = false;
    bool current() {
      if (invalidated ||
          !mounted ||
          !identical(repo, owner) ||
          !owner.signedIn ||
          owner.role != 'parent' ||
          (owner.endpoint, owner.sessionTag, owner.generation, owner.userId) !=
              identity) {
        invalidated = true;
        return false;
      }
      final row = owner
          .rows('grades')
          .where((row) => row['id'] == shown['id'])
          .firstOrNull;
      if (row == null ||
          row['revision'] != shown['revision'] ||
          row['posted_amount'] != shown['posted_amount']) {
        invalidated = true;
        return false;
      }
      return owner.online;
    }

    final posted = shown['posted_amount'];
    if (shown['revision'] is! String || posted is! int || !current()) return;
    final moneyText = posted > 0
        ? 'Ранее за эту оценку начислено $posted монет. При удалении они спишутся. Если монеты уже потрачены, баланс может стать отрицательным.'
        : posted < 0
        ? 'За эту оценку списано ${-posted} монет. При удалении они вернутся на баланс.'
        : 'За эту оценку монеты не начислялись и не списывались.';
    setState(() => gradeAction = true);
    void changed() {
      current();
    }

    owner.addListener(changed);
    try {
      var closing = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AnimatedBuilder(
          animation: owner,
          builder: (_, _) {
            final available = current();
            void close(bool answer) {
              if (closing ||
                  !dialogContext.mounted ||
                  ModalRoute.of(dialogContext)?.isCurrent != true) {
                return;
              }
              if (answer && !current()) return;
              closing = true;
              Navigator.pop(dialogContext, answer);
            }

            return AlertDialog(
              title: const Text('Удалить ошибочную оценку?'),
              scrollable: true,
              content: Text(
                available
                    ? '${gradeTitle(shown, subjects)} · ${shown['grade']}\n${shown['date']}\n\n$moneyText\n\nОжидающие штрафы за эту оценку отменятся. Уже выданные деньги не возвращаются автоматически. Запись об отмене останется в истории.'
                    : 'Оценка, монеты или доступ изменились. Закройте окно и проверьте запись заново. Для удаления нужен интернет.',
              ),
              actions: [
                TextButton(
                  onPressed: () => close(false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  key: const ValueKey('confirm-delete-grade'),
                  onPressed: available ? () => close(true) : null,
                  child: const Text('Удалить оценку'),
                ),
              ],
            );
          },
        ),
      );
      if (confirmed != true || !current()) return;
      await run(() {
        if (!current()) {
          throw ApiFailure(409, 'Данные изменились. Откройте оценку заново.');
        }
        return owner.mutate('/v1/grades/${shown['id']}', {
          'expected_revision': shown['revision'],
          'expected_posted': posted,
        }, method: 'DELETE');
      });
    } finally {
      owner.removeListener(changed);
      if (mounted) setState(() => gradeAction = false);
    }
  }

  Widget gradeActions(CalendarResultItem? item, Map<String, dynamic>? grade) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            key: ValueKey(
              item == null
                  ? 'result-edit-grade-${grade!['id']}'
                  : 'result-grade-${item.key}',
            ),
            onPressed:
                busy ||
                    gradeAction ||
                    !repo.online ||
                    (grade == null && item?.canGrade != true)
                ? null
                : () => saveGrade(item, grade),
            child: Text(grade == null ? 'Поставить оценку' : 'Изменить оценку'),
          ),
          if (grade != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: ValueKey('result-delete-grade-${grade['id']}'),
              onPressed:
                  busy ||
                      gradeAction ||
                      !repo.online ||
                      grade['revision'] is! String ||
                      grade['posted_amount'] is! int
                  ? null
                  : () => deleteGrade(grade),
              child: const Text('Удалить оценку'),
            ),
            if (grade['revision'] is! String || grade['posted_amount'] is! int)
              const Text('Обновите данные семьи, чтобы удалить оценку.'),
          ],
        ],
      );

  Widget historyGrade(Map<String, dynamic> grade) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: ValueKey('result-history-${grade['id']}'),
            contentPadding: EdgeInsets.zero,
            title: Text('${gradeTitle(grade, subjects)} · ${grade['grade']}'),
            subtitle: Text(grade['note'] as String? ?? ''),
            onTap: repo.role == 'parent' && !busy && !gradeAction && repo.online
                ? () => saveGrade(null, grade)
                : null,
          ),
          if (repo.role == 'parent') gradeActions(null, grade),
        ],
      ),
    ),
  );

  bool mayConfirm(Map<String, dynamic> task) =>
      repo.role == 'parent' ||
      (repo.role == 'relative' &&
          repo.snapshot!['user']['review_tasks'] == 1 &&
          (task['author_id'] == repo.userId ||
              task['reviewer_id'] == repo.userId));

  Widget taskResult(CalendarResultItem item) {
    final task = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(item.entry.source!)) as Map,
    );
    final selectedDay = day;
    final view = captureTaskViewAccess();
    final taskBusy = busy || gradeAction || _taskInteractionOpen;
    final active = [
      'assigned',
      'returned',
      'submitted',
    ].contains(task['status']);
    final approved = task['financial_approved'] == 1;
    final photoReady =
        task['require_photo'] != 1 || task['status'] == 'submitted';
    final names = {
      for (final member in repo.rows('members')) member['id']: member['name'],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spacedFormItems([
        Text('От ${names[task['author_id']] ?? 'участника семьи'}'),
        Text(taskKindText(task)),
        Text(taskTermsText(task)),
        Text(statusText(task['status'] as String)),
        if (!approved && active)
          const Text('Награда ожидает согласования родителем'),
        if (repo.role == 'child' &&
            ['assigned', 'returned'].contains(task['status']))
          if (task['require_photo'] == 1)
            OutlinedButton(
              onPressed: taskBusy
                  ? null
                  : () {
                      if (!taskViewCurrent(view, selectedDay) ||
                          repo.role != 'child') {
                        return;
                      }
                      openCalendarTask(
                        context,
                        view.repository,
                        widget.perform,
                        task['id'] as String,
                        item.entry.start,
                      );
                    },
              child: const Text('Отправить результат с фотографией'),
            )
          else
            FilledButton(
              key: ValueKey('result-submit-${task['id']}'),
              onPressed: taskBusy
                  ? null
                  : () => taskAction(
                      task,
                      _SchoolTaskAction.submit,
                      view,
                      selectedDay,
                    ),
              child: const Text('Готово — отправить на проверку'),
            ),
        if (repo.role == 'child' && task['status'] == 'submitted')
          const Text(
            'Взрослый проверит результат. После подтверждения начислится награда.',
          ),
        if (mayConfirm(task) && active) ...[
          if (!photoReady)
            const Text('Сначала нужна фотография результата от ребёнка'),
          FilledButton.icon(
            key: ValueKey('result-complete-${task['id']}'),
            onPressed: taskBusy || !repo.online || !approved || !photoReady
                ? null
                : () => taskAction(
                    task,
                    _SchoolTaskAction.complete,
                    view,
                    selectedDay,
                  ),
            icon: const Icon(Icons.check),
            label: const Text('Подтвердить выполнение'),
          ),
          if (!approved && repo.role == 'parent')
            OutlinedButton(
              onPressed: taskBusy || !repo.online
                  ? null
                  : () => taskAction(
                      task,
                      _SchoolTaskAction.approveFinances,
                      view,
                      selectedDay,
                    ),
              child: const Text('Согласовать награду'),
            ),
        ],
        if (task['status'] == 'completed') Text(taskAwardedText(task)),
        if (canMarkTaskNotCompleted(repo.snapshot!['user'], task))
          OutlinedButton(
            key: ValueKey('result-not-completed-${task['id']}'),
            onPressed:
                taskBusy || !repo.online || (taskIsRequired(task) && !approved)
                ? null
                : () => taskAction(
                    task,
                    _SchoolTaskAction.notCompleted,
                    view,
                    selectedDay,
                  ),
            child: Text(
              taskIsRequired(task)
                  ? 'Не выполнено — назначить штраф'
                  : 'Закрыть без выполнения',
            ),
          ),
      ]),
    );
  }

  Widget eventResult(
    CalendarResultItem item,
    List<Map<String, dynamic>> grades,
  ) {
    final grade = grades.where(item.matchesGrade).firstOrNull;
    return Card(
      key: ValueKey('result-${item.key}'),
      color: eventBackground(item.entry),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: spacedFormItems([
            Text(
              item.timeText,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(item.title, style: Theme.of(context).textTheme.titleLarge),
            if (item.activity != null) Text('В событии «${item.entry.title}»'),
            if (item.activity == null && item.entry.note.isNotEmpty)
              Text(item.entry.note),
            if (item.task)
              taskResult(item)
            else if (repo.role != 'relative') ...[
              Text(
                grade == null
                    ? 'Оценка не указана'
                    : 'Оценка: ${grade['grade']}',
              ),
              if (grade != null && (grade['note'] as String? ?? '').isNotEmpty)
                Text(grade['note'] as String),
              if (repo.role == 'parent') gradeActions(item, grade),
            ],
          ]),
        ),
      ),
    );
  }

  Widget content() {
    final data = repo.snapshot;
    final items = data == null
        ? <CalendarResultItem>[]
        : calendarResultItems(data, day);
    final grades = repo
        .rows('grades')
        .where((grade) => grade['date'] == dateOnly(day))
        .toList();
    final history = grades
        .where((grade) => !items.any((item) => item.matchesGrade(grade)))
        .toList();
    final heading = <Widget>[
      const Text('Школьные предметы и семейные задания на выбранную дату'),
      if (repo.role == 'child')
        const Text(
          'Оценки добавляют родители. Готовые задания отправляй взрослым на проверку.',
        ),
      if (repo.role == 'parent' && !repo.online)
        const Text(
          'Для изменения оценок и подтверждения заданий нужен интернет.',
        ),
      if (repo.role == 'relative' && !repo.online)
        const Text('Для подтверждения заданий нужен интернет.'),
      if (items.isEmpty)
        const Text(
          'На эту дату школьных предметов и заданий нет. Добавьте предметы как занятия внутри события «Школа» в календаре.',
        ),
    ];
    final saved = repo.role == 'relative' ? <Map<String, dynamic>>[] : history;
    final historyHeading = saved.isEmpty
        ? <Widget>[]
        : <Widget>[
            const Text('Сохранённые оценки'),
            const Text(
              'Эти записи сохранены, даже если событие уже изменено или удалено из календаря.',
            ),
          ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: dateControls(),
        ),
        Expanded(
          child: ListView.builder(
            key: ValueKey('calendar-results-list-${dateOnly(day)}'),
            padding: const EdgeInsets.all(20),
            itemCount:
                heading.length +
                items.length +
                historyHeading.length +
                saved.length,
            itemBuilder: (_, index) {
              Widget row;
              final itemIndex = index - heading.length;
              final historyTitleIndex = itemIndex - items.length;
              final historyIndex = historyTitleIndex - historyHeading.length;
              if (index < heading.length) {
                row = heading[index];
              } else if (itemIndex < items.length) {
                row = eventResult(items[itemIndex], grades);
              } else if (historyTitleIndex < historyHeading.length) {
                row = historyHeading[historyTitleIndex];
              } else {
                row = historyGrade(saved[historyIndex]);
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: row,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget dateControls() => Row(
    children: [
      IconButton(
        tooltip: 'Предыдущий день',
        onPressed: day.isAfter(DateTime(2020))
            ? () => setState(
                () => day = DateTime(day.year, day.month, day.day - 1),
              )
            : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: OutlinedButton(
          key: const ValueKey('results-date'),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: day,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100, 12, 31),
            );
            if (picked != null && mounted) setState(() => day = picked);
          },
          child: Text(calendarDateLabel(day), textAlign: TextAlign.center),
        ),
      ),
      IconButton(
        tooltip: 'Следующий день',
        onPressed: day.isBefore(DateTime(2100, 12, 31))
            ? () => setState(
                () => day = DateTime(day.year, day.month, day.day + 1),
              )
            : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repo,
    builder: (context, _) => widget.gradesOnly
        ? Scaffold(
            appBar: gameDesign.value == null
                ? AppBar(title: const Text('Предметы и оценки'))
                : null,
            body: gameDesign.value == null
                ? content()
                : SafeArea(child: content()),
          )
        : content(),
  );
}
