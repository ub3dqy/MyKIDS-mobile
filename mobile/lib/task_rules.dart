import 'package:flutter/material.dart';

import 'repository.dart';
import 'family_action.dart';
import 'task_rewards.dart';
import 'schedule.dart';

bool taskIsRequired(Map<String, dynamic> task) =>
    task.containsKey('is_required')
    ? task['is_required'] == 1 || task['is_required'] == true
    : (task['penalty'] as num? ?? 0) > 0;

String taskKindText(Map<String, dynamic> task) =>
    taskIsRequired(task) ? 'Обязательное задание' : 'Необязательное задание';

String taskTermsText(Map<String, dynamic> task) {
  final options = taskRewardOptions(task);
  final reward = task['status'] == 'completed'
      ? taskAwardedText(task)
      : options != null
      ? 'Награда после проверки:\n${taskRewardRulesText(options)}.'
      : task['reward'] == 0
      ? 'Награды за выполнение нет.'
      : 'Награда после проверки: ${task['reward']} монет.';
  final terms = taskIsRequired(task)
      ? '$reward Штраф за невыполнение: ${task['penalty']} монет, только после подтверждения взрослого.'
      : '$reward Штрафа нет.';
  return task['require_photo'] == 1
      ? '$terms Нужно фотографий: ${task['required_photos'] ?? 1} или больше.'
      : terms;
}

String taskReviewerText(
  Map<String, dynamic> task,
  List<Map<String, dynamic>> members,
) => task['reviewer_id'] == null
    ? 'Проверяет: мама или папа'
    : 'Проверяет: ${members.where((member) => member['id'] == task['reviewer_id']).firstOrNull?['name'] ?? 'участник семьи'}';

bool canReviewTask(Map<String, dynamic> user, Map<String, dynamic> task) =>
    user['role'] == 'parent' ||
    (user['role'] == 'relative' &&
        user['review_tasks'] == 1 &&
        [task['author_id'], task['reviewer_id']].contains(user['id']));

bool canMarkTaskNotCompleted(
  Map<String, dynamic> user,
  Map<String, dynamic> task,
) =>
    canReviewTask(user, task) &&
    ['assigned', 'returned', 'submitted'].contains(task['status']) &&
    DateTime.parse(task['planned_end'] as String? ?? task['due_at'] as String)
        .isBefore(DateTime.now());

Future<bool> confirmTaskFinances(
  BuildContext context,
  FamilyRepository repository,
  Map<String, dynamic> task, {
  FamilyActionAccess? access,
}) async =>
    await showFamilyActionDialog<bool>(
      context: context,
      builder: (_) =>
          _FinancialConsent(repository: repository, task: task, access: access),
    ) ??
    false;

class _FinancialConsent extends StatefulWidget {
  final FamilyRepository repository;
  final Map<String, dynamic> task;
  final FamilyActionAccess? access;
  const _FinancialConsent({
    required this.repository,
    required this.task,
    this.access,
  });

  @override
  State<_FinancialConsent> createState() => _FinancialConsentState();
}

class _FinancialConsentState extends State<_FinancialConsent> {
  late final String session;
  late final int generation;
  bool closing = false;

  @override
  void initState() {
    super.initState();
    session = widget.repository.sessionTag;
    generation = widget.repository.generation;
    widget.repository.addListener(changed);
    widget.access?.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void close(bool consent) {
    if (closing) return;
    setState(() => closing = true);
    Navigator.pop(context, consent);
  }

  @override
  void dispose() {
    widget.repository.removeListener(changed);
    widget.access?.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repository, task = widget.task;
    final owns =
        repo.signedIn &&
        repo.sessionTag == session &&
        repo.generation == generation &&
        (widget.access?.valid ?? true) &&
        repo.role == 'parent';
    final current = repo
        .rows('tasks')
        .where((t) => t['id'] == task['id'])
        .firstOrNull;
    final scope = task['financial_approval_scope'];
    final valid =
        owns &&
        repo.online &&
        task['version'] is int &&
        (task['version'] as int) >= 1 &&
        current != null &&
        current['version'] == task['version'] &&
        current['financial_approved'] == 0 &&
        current['financial_approval_scope'] == scope &&
        const ['single', 'repeat'].contains(scope);
    return AlertDialog(
      scrollable: true,
      title: Text(
        valid ? 'Согласовать условия?' : 'Нужно открыть задание заново',
      ),
      content: Text(
        !owns
            ? 'Семейный доступ изменился. Закройте это окно.'
            : !repo.online
            ? 'Нет связи с сервером. Согласование доступно после подключения.'
            : !valid
            ? 'Условия задания изменились или уже согласованы. Обновите данные и откройте задание заново.'
            : '${task['title']}\n\n${taskTermsText(task)}\n\n'
                  '${scope == 'repeat' ? 'Такие же условия согласуются для всех дней этого повтора, включая будущие. Отдельно изменённые суммы нужно согласовать отдельно.' : 'Согласуются условия только этого задания. Другие дни повтора сохранят свои условия.'}'
                  '\n\nСейчас монеты не начисляются и не списываются.',
      ),
      actions: [
        TextButton(
          onPressed: closing ? null : () => close(false),
          child: Text(valid ? 'Вернуться' : 'Закрыть'),
        ),
        if (valid)
          FilledButton(
            key: const ValueKey('confirm-task-finances'),
            onPressed: closing ? null : () => close(true),
            child: const Text('Согласовать'),
          ),
      ],
    );
  }
}

Future<bool> confirmTaskNotCompleted(
  BuildContext context,
  Map<String, dynamic> task, {
  FamilyActionAccess? access,
}) async =>
    await showFamilyActionDialog<bool>(
      context: context,
      builder: (context) => FamilyActionDialog<bool>(
        access: access,
        builder: (context, close) => AlertDialog(
          scrollable: true,
          title: Text(
            taskIsRequired(task)
                ? 'Штраф: ${task['penalty']} монет'
                : 'Закрыть без выполнения?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task['title'] as String),
              Text(
                taskCalendarTimeText(access?.repository.snapshot, task) ??
                    'Срок: ${familyDateTimeText(access?.repository.snapshot, task['due_at'] as String)}',
              ),
              const SizedBox(height: 16),
              Text(
                'Вы подтверждаете, что задание не выполнено в назначенное время${task['status'] == 'submitted' ? ' после проверки результата ребёнка' : ''}. '
                '${taskIsRequired(task) ? 'Спишется вся сумма, даже при нулевом балансе. Баланс может стать отрицательным.' : 'Награда не начисляется, штрафа нет.'}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => close(null),
              child: const Text('Вернуться'),
            ),
            FilledButton(
              onPressed: () => close(true),
              child: Text(
                taskIsRequired(task)
                    ? 'Списать ${task['penalty']} монет'
                    : 'Закрыть задание',
              ),
            ),
          ],
        ),
      ),
    ) ??
    false;
