import 'package:flutter/material.dart';

import 'activity_lists.dart';
import 'design_system.dart';
import 'design_today.dart';
import 'calendar.dart';
import 'assistant_rules.dart';
import 'calendar_screen.dart';
import 'child_visuals.dart';
import 'repository.dart';
import 'schedule.dart';
import 'task_summary.dart';
import 'visuals.dart';

class FamilyCoinButton extends StatelessWidget {
  final int amount;
  final bool online;
  final VoidCallback onPressed;
  const FamilyCoinButton({
    super.key,
    required this.amount,
    required this.online,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: online
        ? 'Открыть семейные монеты'
        : 'Сохранённый баланс. Открыть монеты',
    child: Semantics(
      label: 'Семейные монеты: $amount${online ? '' : ', сохранённый баланс'}',
      button: true,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: gameDesign.value?.onHeader ?? Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (gameDesign.value != null)
                const GameIcon(3, size: 28)
              else
                Image.asset(
                  'assets/generated/coin-v1.png',
                  width: 26,
                  height: 26,
                ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 60),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$amount',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ChildToday extends StatelessWidget {
  final FamilyRepository repository;
  final DateTime? now;
  final ValueChanged<int> openPage;
  final VoidCallback? onOverview;
  const ChildToday({
    super.key,
    required this.repository,
    required this.openPage,
    this.now,
    this.onOverview,
  });
  @override
  Widget build(BuildContext context) {
    if (gameDesign.value != null) {
      return GameToday(
        repository: repository,
        now: now,
        openPage: openPage,
        onOverview: onOverview,
      );
    }
    final repo = repository;
    final tasks =
        repo
            .rows('tasks')
            .where((t) => !['cancelled', 'not_completed'].contains(t['status']))
            .where((t) => taskIsForToday(repo.snapshot, t))
            .toList()
          ..sort(compareTaskTime);
    final done = tasks.where((t) => t['status'] == 'completed').length;
    final waiting = tasks.where((t) => t['status'] == 'submitted').length;
    final active = tasks
        .where((t) => ['assigned', 'returned'].contains(t['status']))
        .toList();
    final lessons = calendarDay(repo.snapshot!, familyClock(repo.snapshot));
    final credits =
        repo
            .rows('ledger')
            .where(
              (e) =>
                  e['child_id'] == repo.userId &&
                  ['task', 'grade'].contains(e['source_type']) &&
                  (e['actual'] as num) > 0,
            )
            .toList()
          ..sort(
            (a, b) => (a['created_at'] as String).compareTo(
              b['created_at'] as String,
            ),
          );
    final latest = credits.lastOrNull;
    final preparations = assistantHints(
      repo.snapshot!,
      familyClock(repo.snapshot),
    ).map((hint) => hint.message).toSet().toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Привет, ${repo.snapshot?['user']?['name']}!',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const Text('Твой день — твоё приключение!'),
        const SizedBox(height: 16),
        FamilySection(
          title: 'Твой день',
          icon: 1,
          children: [
            if (preparations.isNotEmpty)
              ActivityWindow(
                key: const ValueKey('child-preparations'),
                count: preparations.length,
                filterKey: (repo.sessionTag, repo.generation),
                compactWhenShort: true,
                showCount: false,
                emptyText: '',
                itemBuilder: (_, index) =>
                    Text('Подготовь: ${preparations[index]}'),
              ),
            if (onOverview != null)
              FilledButton(
                onPressed: onOverview,
                child: const Text('Помощник, расскажи о дне!'),
              ),
            if (lessons.isEmpty) const Text('Занятия пока не добавлены'),
            for (final lesson in lessons.take(4))
              CalendarTile(
                entry: lesson,
                conflict: calendarConflicts(lessons).contains(lesson.key),
                child: true,
                onTap: () => openPage(1),
              ),
            if (lessons.length > 4)
              Text('Ещё ${lessons.length - 4} в календаре'),
            TextButton(
              onPressed: () => openPage(1),
              child: const Text('Весь день в календаре'),
            ),
          ],
        ),
        FamilySection(
          title: 'Мои задания',
          icon: 2,
          children: [
            Row(
              children: [
                const ChildMotion(size: 92),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tasks.isEmpty
                            ? 'Всё начинается с маленького шага!'
                            : 'Проверено $done из ${tasks.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (tasks.isNotEmpty)
                        LinearProgressIndicator(
                          key: const ValueKey('today-task-progress'),
                          value: done / tasks.length,
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        waiting > 0
                            ? 'На проверке: $waiting. Ты молодец!'
                            : tasks.isEmpty
                            ? 'Семья добавит задания, а я помогу о них помнить.'
                            : active.isEmpty
                            ? 'Задания проверены. Отличная работа!'
                            : 'Выбери задание и попробуй свои силы.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            for (final task in active.take(2))
              ListTile(
                leading: const FamilyIcon(2),
                title: Text(task['title'] as String),
                subtitle: TaskSummary(snapshot: repo.snapshot, task: task),
                onTap: () => openPage(2),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => openPage(2),
              child: const Text('Открыть задания'),
            ),
          ],
        ),
        if (latest != null)
          FamilySection(
            title: 'Твоя последняя победа',
            icon: 3,
            children: [
              Text('+${latest['actual']} монет · ${latest['reason']}'),
              const Text('Семья заметила твои старания!'),
            ],
          ),
        const ChildHeader(
          art: 3,
          title: 'Семья рядом',
          message: 'Расскажи о своей победе или просто поздоровайся!',
        ),
        FilledButton(
          onPressed: () => openPage(4),
          child: const Text('Чаты и звонки'),
        ),
        FutureBuilder(
          future: repo.pending(),
          builder: (context, data) => !data.hasData || data.data!.isEmpty
              ? const SizedBox.shrink()
              : PendingActivities(
                  rows: data.data!,
                  filterKey: (repo.sessionTag, repo.generation),
                ),
        ),
      ],
    );
  }
}
