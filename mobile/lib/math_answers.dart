import 'package:flutter/material.dart';

import 'repository.dart';

Future<void> openMathAnswers(
  BuildContext context,
  FamilyRepository repository,
  String taskId,
) async {
  if (!repository.signedIn || repository.role != 'parent') return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => MathAnswersScreen(repository: repository, taskId: taskId),
    ),
  );
}

/// Answers live only in this parent's open page, never in the shared snapshot.
class MathAnswersScreen extends StatefulWidget {
  final FamilyRepository repository;
  final String taskId;
  const MathAnswersScreen({
    super.key,
    required this.repository,
    required this.taskId,
  });

  @override
  State<MathAnswersScreen> createState() => _MathAnswersScreenState();
}

class _MathAnswersScreenState extends State<MathAnswersScreen> {
  FamilyRepository get repo => widget.repository;
  late final String owner;
  late final int generation;
  bool revoked = false, loading = true;
  int requestNumber = 0;
  List<Map<String, dynamic>> days = [];
  Map<String, dynamic>? lesson;
  String? selected, error;

  bool get allowed =>
      !revoked &&
      repo.signedIn &&
      repo.role == 'parent' &&
      owner == repo.sessionTag &&
      generation == repo.generation;
  String get taskPath => '/v1/tasks/${Uri.encodeComponent(widget.taskId)}';

  @override
  void initState() {
    super.initState();
    owner = repo.sessionTag;
    generation = repo.generation;
    repo.addListener(identityChanged);
    loadDays();
  }

  void identityChanged() {
    if (!allowed && mounted) {
      setState(() {
        revoked = true;
        requestNumber++;
        days = [];
        lesson = null;
      });
    }
  }

  void failed(Object failure, int request) {
    if (!mounted || request != requestNumber || !allowed) return;
    setState(() {
      loading = false;
      lesson = null;
      if (failure is ApiFailure && [401, 403].contains(failure.status)) {
        revoked = true;
        days = [];
      } else {
        error = failure is ApiFailure && failure.status == 404
            ? 'Материалы на сервере пока недоступны.'
            : 'Не удалось открыть ответы. Проверьте интернет и попробуйте ещё раз.';
      }
    });
  }

  Future<void> loadDays() async {
    if (!allowed) return;
    final request = ++requestNumber;
    setState(() {
      loading = true;
      error = null;
      lesson = null;
    });
    try {
      final index = await repo.request('$taskPath/math-answer-sessions');
      if (!mounted || request != requestNumber || !allowed) return;
      final choices = (index['lessons'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final dates = choices.map((row) => row['date']).toSet();
      if (dates.length != choices.length ||
          choices.isEmpty ||
          choices.any(
            (row) => row['date'] is! String || row['title'] is! String,
          )) {
        throw const FormatException('Incomplete lesson index');
      }
      final suggested = index['suggested_date'];
      setState(() {
        days = choices;
        selected = dates.contains(selected)
            ? selected
            : suggested is String && dates.contains(suggested)
            ? suggested
            : null;
        loading = false;
      });
      if (selected != null) await loadLesson(selected!);
    } catch (failure) {
      failed(failure, request);
    }
  }

  Future<void> loadLesson(String day) async {
    if (!allowed) return;
    final request = ++requestNumber;
    setState(() {
      selected = day;
      lesson = null;
      error = null;
      loading = true;
    });
    try {
      final data = await repo.request(
        '$taskPath/math-answers/${Uri.encodeComponent(day)}',
      );
      if (!mounted || request != requestNumber || !allowed) return;
      if (data['date'] != day ||
          data['title'] is! String ||
          data['tasks'] is! List) {
        throw const FormatException('Wrong lesson');
      }
      final tasks = (data['tasks'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (tasks.length != 6 ||
          tasks.any(
            (task) => [
              'title',
              'prompt',
              'answer',
              'solution',
              'hint',
            ].any((key) => task[key] is! String),
          )) {
        throw const FormatException('Incomplete answers');
      }
      setState(() {
        lesson = {...data, 'tasks': tasks};
        loading = false;
      });
    } catch (failure) {
      failed(failure, request);
    }
  }

  @override
  void dispose() {
    repo.removeListener(identityChanged);
    lesson = null;
    days = [];
    super.dispose();
  }

  String dateLabel(String value) {
    final date = DateTime.tryParse(value);
    return date == null
        ? value
        : '${date.day.toString().padLeft(2, '0')}.'
              '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ответы по математике')),
    body: !allowed
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Ответы доступны только родителям. Откройте задание из родительского профиля.',
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (days.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('math-answer-day-$selected'),
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'День занятия'),
                  hint: const Text('Выберите день'),
                  items: [
                    for (final day in days)
                      DropdownMenuItem(
                        value: day['date'] as String,
                        child: Text(
                          '${dateLabel(day['date'] as String)} · ${day['title']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (day) {
                    if (day != null) loadLesson(day);
                  },
                ),
              if (days.isNotEmpty) const SizedBox(height: 16),
              if (loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (error != null) ...[
                Text(error!),
                TextButton(
                  onPressed: () =>
                      selected == null ? loadDays() : loadLesson(selected!),
                  child: const Text('Повторить'),
                ),
              ],
              if (!loading && error == null && selected == null)
                const Text(
                  'Выберите день из курса 14 октября — 13 ноября 2026 года.',
                ),
              if (lesson != null) ...[
                Text(
                  '${dateLabel(lesson!['date'] as String)} · ${lesson!['title']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final task
                    in (lesson!['tasks'] as List).cast<Map<String, dynamic>>())
                  ExpansionTile(
                    key: ValueKey(
                      'math-answer-${lesson!['date']}-${task['number']}',
                    ),
                    tilePadding: EdgeInsets.zero,
                    title: Text('${task['number']}. ${task['title']}'),
                    subtitle: Text('Ответ: ${task['answer']}'),
                    childrenPadding: const EdgeInsets.only(bottom: 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task['prompt'] as String),
                      const SizedBox(height: 12),
                      Text('Решение: ${task['solution']}'),
                      const SizedBox(height: 12),
                      Text('Подсказка: ${task['hint']}'),
                    ],
                  ),
              ],
            ],
          ),
  );
}
