import 'package:flutter/material.dart';

import 'design_system.dart';

import 'schedule.dart';
import 'task_rewards.dart';

String taskCompactTimeText(
  Map<String, dynamic>? snapshot,
  Map<String, dynamic> task,
) {
  String two(int value) => value.toString().padLeft(2, '0');
  String clock(DateTime value) => '${two(value.hour)}:${two(value.minute)}';
  String date(DateTime value) =>
      '${two(value.day)}.${two(value.month)}'
      '${value.year == familyClock(snapshot).year ? '' : '.${value.year}'}';
  final start = task['planned_start'] as String?;
  final end = task['planned_end'] as String?;
  if (start != null && end != null) {
    final first = familyClock(snapshot, DateTime.parse(start));
    final last = familyClock(snapshot, DateTime.parse(end));
    final finish = dateOnly(first) == dateOnly(last)
        ? clock(last)
        : '${date(last)} ${clock(last)}';
    return '${date(first)} ${clock(first)}–$finish';
  }
  final due = familyClock(snapshot, DateTime.parse(task['due_at'] as String));
  return 'До ${date(due)} ${clock(due)}';
}

String taskCompactRewardText(Map<String, dynamic> task) {
  if (task['status'] == 'completed') {
    final coins = task['awarded_reward'] ?? task['reward'] ?? 0;
    return coins == 0 ? 'Без монет' : '+$coins монет';
  }
  if (['cancelled', 'not_completed'].contains(task['status'])) return '';
  final options = taskRewardOptions(task);
  final coins = task['reward'] as num? ?? 0;
  if (coins == 0) return '';
  return options == null ? '$coins монет' : 'До $coins монет';
}

class TaskSummary extends StatelessWidget {
  final Map<String, dynamic>? snapshot;
  final Map<String, dynamic> task;
  const TaskSummary({super.key, required this.snapshot, required this.task});

  @override
  Widget build(BuildContext context) {
    final reward = taskCompactRewardText(task);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          taskCompactTimeText(snapshot, task),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Wrap(
          spacing: 8,
          children: [
            Text(
              gameDesign.value != null && snapshot?['user']?['role'] == 'child'
                  ? (const {
                          'assigned': 'Можно начать',
                          'completed': 'Проверено',
                          'submitted': 'Проверяют',
                          'returned': 'Попробуй ещё раз',
                        }[task['status']] ??
                        statusText(task['status'] as String))
                  : task['status'] == 'submitted'
                  ? 'Ждёт проверки'
                  : statusText(task['status'] as String),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (reward.isNotEmpty)
              Text(reward, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ],
    );
  }
}

class TaskCompactCard extends StatefulWidget {
  final Map<String, dynamic>? snapshot;
  final Map<String, dynamic> task;
  final List<Widget> main;
  final List<Widget> details;
  const TaskCompactCard({
    super.key,
    required this.snapshot,
    required this.task,
    required this.main,
    required this.details,
  });

  @override
  State<TaskCompactCard> createState() => _TaskCompactCardState();
}

class _TaskCompactCardState extends State<TaskCompactCard> {
  bool expanded = false;

  void toggleDetails() => setState(() => expanded = !expanded);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: toggleDetails,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.task['title'] as String,
                maxLines: expanded ? null : 2,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              TaskSummary(snapshot: widget.snapshot, task: widget.task),
            ],
          ),
        ),
        for (final item in widget.main) ...[const SizedBox(height: 8), item],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: toggleDetails,
            child: Text(expanded ? 'Скрыть подробности' : 'Подробнее'),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 12),
          for (final item in widget.details) ...[
            const SizedBox(height: 8),
            item,
          ],
        ],
      ],
    ),
  );
}
