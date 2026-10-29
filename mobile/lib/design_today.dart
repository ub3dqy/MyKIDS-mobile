import 'package:flutter/material.dart';

import 'calendar.dart';
import 'child_visuals.dart';
import 'design_system.dart';
import 'repository.dart';
import 'schedule.dart';
import 'task_screen.dart';
import 'task_summary.dart';
import 'engagement/engagement_entries.dart';
import 'engagement/engagement_scope.dart';

/// Production screen, also used unchanged in the five review variants.
class GameToday extends StatelessWidget {
  final FamilyRepository repository;
  final DateTime? now;
  final ValueChanged<int> openPage;
  final VoidCallback? onOverview;
  const GameToday({
    super.key,
    required this.repository,
    required this.openPage,
    this.now,
    this.onOverview,
  });

  Future<void> perform(
    BuildContext context,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    try {
      final result = await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] as String? ?? 'Сохранено')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiFailure
                  ? error.message
                  : 'Не удалось выполнить действие. Попробуй ещё раз.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final design = gameDesign.value!;
    final repo = repository;
    final now = familyClock(repo.snapshot, this.now);
    final entries = calendarDay(
      repo.snapshot!,
      now,
    ).where((e) => e.kind != 'task').toList();
    final next =
        entries.where((e) => e.end.isAfter(now)).firstOrNull ??
        entries.lastOrNull;
    final tasks =
        repo
            .rows('tasks')
            .where(
              (t) =>
                  taskIsForToday(repo.snapshot, t, now: now) &&
                  !['cancelled', 'not_completed'].contains(t['status']),
            )
            .toList()
          ..sort(compareTaskTime);
    final done = tasks.where((t) => t['status'] == 'completed').length;
    final waiting = tasks.where((t) => t['status'] == 'submitted').length;
    final active = tasks
        .where((t) => ['assigned', 'returned'].contains(t['status']))
        .toList();
    Widget heading(
      String title,
      String label,
      VoidCallback action, {
      bool mascot = false,
    }) => Row(
      children: [
        if (mascot) ...[const ChildMotion(size: 56), const SizedBox(width: 8)],
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton(
          onPressed: action,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        GameScene(
          title: 'Привет, ${repo.snapshot!['user']['name']}!',
          description: 'Вперёд к открытиям!',
        ),
        if (EngagementScope.maybeOf(context) != null)
          HeroHomeActions(onTasks: () => openPage(2)),
        heading('Твой день', 'Весь день', () => openPage(1), mascot: true),
        if (next == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Занятий пока нет'),
                  const SizedBox(height: 6),
                  Text(
                    'Новые занятия появятся здесь.',
                    style: TextStyle(color: design.muted),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 4,
              ),
              leading: Text(
                clockText(next.start),
                style: TextStyle(
                  color: design.accent,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              title: Text(
                next.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                next.note.isNotEmpty ? next.note : next.timeText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(1),
            ),
          ),
        if (onOverview != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOverview,
              icon: const Icon(Icons.volume_up_outlined, size: 20),
              label: const Text(
                'Расскажи о дне',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
        heading('Мои задания', 'Все', () => openPage(2)),
        if (EngagementScope.maybeOf(context) != null) const AdventureEntry(),
        if (tasks.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Проверено $done из ${tasks.length}',
                  style: TextStyle(color: design.muted, fontSize: 13),
                ),
              ),
              if (waiting > 0)
                Text(
                  'На проверке: $waiting',
                  style: TextStyle(
                    color: design.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          if (design.id == 'islands')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < tasks.length; i++)
                  Container(
                    width: 33,
                    height: 29,
                    decoration: BoxDecoration(
                      color: i < done ? design.accent : design.soft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      i < done ? '✓' : '${i + 1}',
                      style: TextStyle(
                        color: i < done ? Colors.white : design.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            )
          else
            LinearProgressIndicator(value: done / tasks.length),
          const SizedBox(height: 12),
        ],
        for (final task in active.take(2))
          Card(
            child: ListTile(
              leading: GameIcon(task['id'] == 'bag' ? 7 : 6, size: 34),
              title: Text(
                task['title'] as String,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                taskCompactTimeText(repo.snapshot, task),
                style: TextStyle(fontSize: 13, color: design.muted),
              ),
              trailing: Text(
                '${task['reward']}\nмонет',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: design.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
              onTap: () => openCalendarTask(
                context,
                repo,
                (action) => perform(context, action),
                task['id'] as String,
                now,
              ),
            ),
          ),
        if (active.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const ChildMotion(size: 68),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tasks.isEmpty
                          ? 'Новых заданий пока нет. Можно отдохнуть!'
                          : waiting > 0
                          ? 'Ты справился! Семья проверит результат.'
                          : 'Всё проверено. Отличная работа!',
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        if (EngagementScope.maybeOf(context) != null)
          const FamilyMissionEntry(),
        Card(
          color: design.soft,
          child: ListTile(
            leading: const GameIcon(4, size: 37),
            title: const Text(
              'Семья рядом',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: const Text(
              'Чаты, звонки и поддержка близких',
              style: TextStyle(fontSize: 13),
            ),
            trailing: Icon(Icons.arrow_forward_rounded, color: design.accent),
            onTap: () => openPage(4),
          ),
        ),
      ],
    );
  }
}
