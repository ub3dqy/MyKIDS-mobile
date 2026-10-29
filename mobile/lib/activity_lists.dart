import 'dart:convert';

import 'package:flutter/material.dart';

import 'repository.dart';
import 'schedule.dart';
import 'task_summary.dart';

class ActivityFilter extends StatelessWidget {
  final String label, value;
  final Map<String, String> choices;
  final ValueChanged<String> onChanged;
  const ActivityFilter({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey((label, value, jsonEncode(choices))),
    initialValue: value,
    isDense: false,
    isExpanded: true,
    itemHeight: null,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final entry in choices.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

typedef _ActivityOwner = (
  FamilyRepository,
  String,
  String,
  int,
  String,
  String,
);

_ActivityOwner _activityOwner(FamilyRepository repo) => (
  repo,
  repo.endpoint,
  repo.sessionTag,
  repo.generation,
  repo.userId,
  repo.role,
);

/// A bounded, independently scrollable list keeps long histories from pushing
/// the rest of the page out of reach. Rows are built only as they become visible.
class ActivityWindow extends StatefulWidget {
  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final String emptyText;
  final Object filterKey;
  final bool compactWhenShort;
  final bool showCount;
  const ActivityWindow({
    super.key,
    required this.count,
    required this.itemBuilder,
    required this.emptyText,
    required this.filterKey,
    this.compactWhenShort = false,
    this.showCount = true,
  });

  @override
  State<ActivityWindow> createState() => _ActivityWindowState();
}

class _ActivityWindowState extends State<ActivityWindow> {
  final controller = ScrollController();
  @override
  void didUpdateWidget(covariant ActivityWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterKey != widget.filterKey && controller.hasClients) {
      controller.jumpTo(0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.showCount) ...[
        Text('Найдено: ${widget.count}'),
        const SizedBox(height: 8),
      ],
      if (widget.count == 0)
        Text(widget.emptyText)
      else if (widget.compactWhenShort && widget.count <= 3)
        for (var index = 0; index < widget.count; index++)
          Padding(
            padding: EdgeInsets.only(bottom: index == widget.count - 1 ? 0 : 8),
            child: widget.itemBuilder(context, index),
          )
      else
        SizedBox(
          height: MediaQuery.sizeOf(context).height.clamp(400, 900) * .4,
          child: Scrollbar(
            controller: controller,
            thumbVisibility: true,
            interactive: true,
            child: ListView.builder(
              controller: controller,
              primary: false,
              padding: const EdgeInsets.only(right: 12),
              itemCount: widget.count,
              itemBuilder: widget.itemBuilder,
            ),
          ),
        ),
    ],
  );
}

class PendingActivities extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Object filterKey;
  const PendingActivities({
    super.key,
    required this.rows,
    required this.filterKey,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ожидают отправки или исправления: ${rows.length}'),
          const SizedBox(height: 8),
          ActivityWindow(
            key: const ValueKey('pending-activities'),
            count: rows.length,
            filterKey: filterKey,
            compactWhenShort: true,
            showCount: false,
            emptyText: 'Все записи отправлены',
            itemBuilder: (_, index) {
              final row = rows[index];
              final error = row['error'] as String?;
              if (error == null || error.isEmpty) {
                return const ListTile(
                  title: Text('Результат сохранён'),
                  subtitle: Text('Отправим после подключения'),
                );
              }
              return ExpansionTile(
                key: ValueKey(row['id'] ?? index),
                title: const Text('Нужно исправить перед отправкой'),
                subtitle: Text(
                  error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(error),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class TodayTaskList extends StatefulWidget {
  final FamilyRepository repository;
  final VoidCallback onOpen;
  const TodayTaskList({
    super.key,
    required this.repository,
    required this.onOpen,
  });

  @override
  State<TodayTaskList> createState() => _TodayTaskListState();
}

class _TodayTaskListState extends State<TodayTaskList> {
  String period = 'today', status = 'all';
  _ActivityOwner? owner;

  bool current(_ActivityOwner shown) =>
      mounted &&
      _activityOwner(widget.repository) == shown &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    final shownOwner = _activityOwner(repo);
    if (owner != shownOwner) {
      owner = shownOwner;
      period = 'today';
      status = 'all';
    }
    final now = familyClock(repo.snapshot);
    final today = DateTime(now.year, now.month, now.day);
    final rows = repo.rows('tasks').where((row) {
      if (status != 'all' && row['status'] != status) return false;
      if (period == 'all') return true;
      final due = familyClock(
        repo.snapshot,
        DateTime.parse(
          row['planned_start'] as String? ?? row['due_at'] as String,
        ),
      );
      final day = DateTime(due.year, due.month, due.day);
      if (period == 'week') {
        return !day.isBefore(today) &&
            day.isBefore(today.add(const Duration(days: 7)));
      }
      return taskIsForToday(repo.snapshot, row);
    }).toList()..sort(compareTaskTime);
    return KeyedSubtree(
      key: ValueKey(shownOwner),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ActivityFilter(
            label: 'Период заданий',
            value: period,
            choices: const {
              'today': 'Сегодня и просроченные',
              'week': 'Ближайшие 7 дней',
              'all': 'Все даты',
            },
            onChanged: (value) {
              if (current(shownOwner)) setState(() => period = value);
            },
          ),
          const SizedBox(height: 12),
          ActivityFilter(
            label: 'Состояние задания',
            value: status,
            choices: const {
              'all': 'Все состояния',
              'assigned': 'Выдано',
              'submitted': 'На проверке',
              'returned': 'Нужно исправить',
              'completed': 'Выполнено',
              'not_completed': 'Не выполнено',
              'cancelled': 'Отменено',
            },
            onChanged: (value) {
              if (current(shownOwner)) setState(() => status = value);
            },
          ),
          if (period != 'today' || status != 'all')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  if (!current(shownOwner)) return;
                  setState(() {
                    period = 'today';
                    status = 'all';
                  });
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Сбросить фильтры'),
              ),
            ),
          const SizedBox(height: 12),
          ActivityWindow(
            filterKey: (period, status),
            count: rows.length,
            emptyText: 'По выбранным фильтрам заданий нет',
            itemBuilder: (_, index) {
              final row = rows[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row['title']),
                subtitle: TaskSummary(snapshot: repo.snapshot, task: row),
                onTap: () {
                  if (current(shownOwner)) widget.onOpen();
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

String _actionGroup(String action) {
  final prefix = action.split('.').first;
  return switch (prefix) {
    'task' || 'program' => 'tasks',
    'schedule' => 'calendar',
    'grade' || 'subject' => 'grades',
    'penalty' || 'redemption' || 'reward' => 'money',
    'call' => 'calls',
    _ => 'family',
  };
}

class ActionHistory extends StatefulWidget {
  final FamilyRepository repository;
  const ActionHistory({super.key, required this.repository});
  @override
  State<ActionHistory> createState() => _ActionHistoryState();
}

class _ActionHistoryState extends State<ActionHistory> {
  String period = 'week', group = 'all', actor = 'all';
  _ActivityOwner? owner;

  bool current(_ActivityOwner shown) =>
      mounted &&
      _activityOwner(widget.repository) == shown &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    final shownOwner = _activityOwner(repo);
    if (owner != shownOwner) {
      owner = shownOwner;
      period = 'week';
      group = 'all';
      actor = 'all';
    }
    final all = repo.rows('audit');
    final members = {
      for (final row in repo.rows('members'))
        row['id'] as String: row['name'] as String,
    };
    final actors = {
      'all': 'Все участники',
      for (final row in all)
        if (row['actor_id'] is String)
          row['actor_id'] as String:
              members[row['actor_id']] ?? 'Бывший участник',
    };
    // A fresh snapshot can remove the selected actor's last history entry.
    if (!actors.containsKey(actor)) actor = 'all';
    final selectedActor = actor;
    final now = familyClock(repo.snapshot);
    final today = DateTime(now.year, now.month, now.day);
    final days = {'today': 1, 'week': 7, 'month': 30}[period];
    final rows =
        all.where((row) {
          if (group != 'all' && _actionGroup(row['action']) != group) {
            return false;
          }
          if (selectedActor != 'all' && row['actor_id'] != selectedActor) {
            return false;
          }
          if (days == null) return true;
          final clock = familyClock(
            repo.snapshot,
            DateTime.parse(row['created_at']),
          );
          final day = DateTime(clock.year, clock.month, clock.day);
          return !day.isBefore(today.subtract(Duration(days: days - 1))) &&
              !day.isAfter(today);
        }).toList()..sort(
          (a, b) =>
              DateTime.parse(b['created_at'])
                  .compareTo(DateTime.parse(a['created_at'])),
        );
    return KeyedSubtree(
      key: ValueKey(shownOwner),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'История действий',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (all.length >= 1000)
            const Text('Показаны последние 1000 действий семьи'),
          const SizedBox(height: 12),
          ActivityFilter(
            label: 'Период истории',
            value: period,
            choices: const {
              'today': 'Сегодня',
              'week': 'Последние 7 дней',
              'month': 'Последние 30 дней',
              'all': 'Вся доступная история',
            },
            onChanged: (value) {
              if (current(shownOwner)) setState(() => period = value);
            },
          ),
          const SizedBox(height: 12),
          ActivityFilter(
            label: 'Вид действия',
            value: group,
            choices: const {
              'all': 'Все действия',
              'tasks': 'Задания',
              'calendar': 'Календарь',
              'grades': 'Предметы и оценки',
              'money': 'Монеты и награды',
              'calls': 'Звонки',
              'family': 'Семейные настройки',
            },
            onChanged: (value) {
              if (current(shownOwner)) setState(() => group = value);
            },
          ),
          const SizedBox(height: 12),
          ActivityFilter(
            key: ValueKey(selectedActor),
            label: 'Участник',
            value: selectedActor,
            choices: actors,
            onChanged: (value) {
              if (current(shownOwner)) setState(() => actor = value);
            },
          ),
          if (period != 'week' || group != 'all' || selectedActor != 'all')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  if (!current(shownOwner)) return;
                  setState(() {
                    period = 'week';
                    group = 'all';
                    actor = 'all';
                  });
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Сбросить фильтры'),
              ),
            ),
          const SizedBox(height: 12),
          ActivityWindow(
            filterKey: (period, group, selectedActor),
            count: rows.length,
            emptyText: 'По выбранным фильтрам действий нет',
            itemBuilder: (_, index) {
              final row = rows[index];
              return ListTile(
                key: ValueKey('history-row-$index'),
                contentPadding: EdgeInsets.zero,
                title: Text(historyText(row['action'])),
                subtitle: Text(
                  '${familyDateTimeText(repo.snapshot, row['created_at'])} · ${members[row['actor_id']] ?? 'Бывший участник'}',
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
