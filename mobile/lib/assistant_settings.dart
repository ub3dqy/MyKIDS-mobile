import 'package:flutter/material.dart';

import 'assistant_rules.dart';
import 'family_action.dart';
import 'forms.dart';
import 'repository.dart';

class AssistantSettings extends StatefulWidget {
  final FamilyRepository repository;
  const AssistantSettings({super.key, required this.repository});

  @override
  State<AssistantSettings> createState() => _AssistantSettingsState();
}

class _AssistantSettingsState extends State<AssistantSettings> {
  late final FamilyRepository repository;
  late final FamilyActionAccess access;
  final pendingRemovals = <String>{};
  bool interactionOpen = false;

  @override
  void initState() {
    super.initState();
    repository = widget.repository;
    access = FamilyActionAccess(
      repository,
      permitted: () =>
          mounted &&
          identical(repository, widget.repository) &&
          repository.role == 'parent',
    );
    repository.addListener(changed);
    access.addListener(changed);
  }

  void changed() {
    // Observe revocation immediately, even if access returns before the next frame.
    final valid = access.valid;
    if (valid) {
      final present = assistantRules(repository.snapshot!)
          .map((rule) => rule['id'])
          .toSet();
      pendingRemovals.removeWhere((id) => !present.contains(id));
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AssistantSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(repository, widget.repository)) access.invalidate();
  }

  @override
  void dispose() {
    repository.removeListener(changed);
    access.removeListener(changed);
    access.invalidate();
    // An open form may outlive this route and must first hide its private fields.
    if (!interactionOpen) access.dispose();
    super.dispose();
  }

  void finishInteraction() {
    interactionOpen = false;
    if (mounted) {
      setState(() {});
    } else {
      access.dispose();
    }
  }

  Future<void> edit(BuildContext context, [Map<String, dynamic>? rule]) async {
    if (interactionOpen ||
        !access.valid ||
        pendingRemovals.contains(rule?['id'])) {
      return;
    }
    setState(() => interactionOpen = true);
    try {
      await familyForm(
        context,
        rule == null ? 'Новое правило помощника' : 'Правило помощника',
        [
          FamilyField('title', 'Название правила', initial: rule?['title']),
          FamilyField(
            'keywords',
            'Названия занятий через запятую',
            kind: 'note',
            initial: (rule?['keywords'] as List?)?.join(', '),
            validator: (value) {
              final words = (value as String? ?? '')
                  .split(',')
                  .map((word) => word.trim())
                  .where((word) => word.isNotEmpty)
                  .toList();
              return words.isEmpty
                  ? 'Укажите хотя бы одно название занятия'
                  : words.length > 16 || words.any((word) => word.length > 100)
                  ? 'Укажите до 16 названий, каждое не длиннее 100 символов'
                  : null;
            },
          ),
          FamilyField(
            'message',
            'Что ребёнку нужно сделать или взять с собой',
            kind: 'note',
            initial: rule?['message'],
            validator: (value) => (value as String? ?? '').length > 1000
                ? 'Напоминание должно содержать не более 1000 символов'
                : null,
          ),
          FamilyField(
            'minutes_before',
            'За сколько минут до занятия напомнить',
            kind: 'int',
            initial: rule?['minutes_before'] ?? 45,
            validator: (value) => value is! int || value < 1 || value > 1440
                ? 'Укажите от 1 до 1440 минут'
                : null,
          ),
          FamilyField(
            'enabled',
            'Напоминание включено',
            kind: 'bool',
            initial: rule?['enabled'] ?? true,
          ),
        ],
        access: access,
        onSave: (data) {
          access.requireCurrent();
          final body = {
            ...data,
            'keywords': (data['keywords'] as String)
                .split(',')
                .map((word) => word.trim())
                .where((word) => word.isNotEmpty)
                .toSet()
                .toList(),
          };
          return repository.mutate(
            '/v1/assistant${rule == null ? '' : '/${rule['id']}'}',
            body,
            method: rule == null ? 'POST' : 'PUT',
          );
        },
      );
    } finally {
      finishInteraction();
    }
  }

  Future<void> remove(BuildContext context, Map<String, dynamic> rule) async {
    final id = rule['id'] as String;
    if (interactionOpen || !access.valid || pendingRemovals.contains(id)) {
      return;
    }
    setState(() => interactionOpen = true);
    try {
      final confirm = await showFamilyActionDialog<bool>(
        context: context,
        builder: (context) => FamilyActionDialog<bool>(
          access: access,
          builder: (context, close) => AlertDialog(
            scrollable: true,
            title: const Text('Удалить правило?'),
            content: Text(rule['title'] as String),
            actions: [
              TextButton(
                onPressed: () => close(null),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => close(true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ),
      );
      if (confirm != true ||
          !access.valid ||
          !context.mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      access.requireCurrent();
      final result = await repository.mutate(
        '/v1/assistant/$id',
        {},
        method: 'DELETE',
      );
      if (access.valid && result['queued'] == true) {
        pendingRemovals.add(id);
        showMessage(
          'Связь оборвалась. Удаление сохранено для сверки. Обновите список после подключения.',
        );
      }
    } on QueuedCommandFailure {
      if (access.valid) {
        pendingRemovals.add(id);
        showMessage(
          'Связь оборвалась. Удаление сохранено для сверки. Обновите список после подключения.',
        );
      }
    } catch (failure) {
      showMessage(
        failure is ApiFailure
            ? failure.message
            : 'Не удалось удалить правило. Проверьте соединение',
      );
    } finally {
      finishInteraction();
    }
  }

  void showMessage(String message) {
    if (!mounted ||
        !access.valid ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> refresh() async {
    if (!access.valid) return;
    try {
      await repository.sync();
      if (!access.valid) return;
      final commands = await repository.pending();
      if (!access.valid) return;
      final failedRemoval = pendingRemovals.any(
        (id) => commands.any(
          (row) =>
              row['path'] == '/v1/assistant/$id' && row['state'] == 'failed',
        ),
      );
      setState(
        () => pendingRemovals.removeWhere(
          (id) => !commands.any(
            (row) =>
                row['path'] == '/v1/assistant/$id' && row['state'] == 'pending',
          ),
        ),
      );
      if (failedRemoval) {
        showMessage(
          'Удаление не выполнено. Проверьте правило перед повторной попыткой.',
        );
      }
    } catch (failure) {
      showMessage(
        failure is ApiFailure
            ? failure.message
            : 'Не удалось обновить список. Проверьте соединение.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Настройки помощника')),
    body: SafeArea(
      top: false,
      child: !access.valid
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Семейный доступ изменился. Откройте настройки заново.',
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Помощник ищет названия событий и занятий внутри них в календаре. '
                    'Он показывает, что подготовить на сегодня, и напоминает ребёнку перед занятием. '
                    'Время напоминания по умолчанию — 45 минут.',
                  ),
                  const SizedBox(height: 16),
                  for (final rule in assistantRules(repository.snapshot ?? {}))
                    Card(
                      child: ListTile(
                        title: Text(rule['title'] as String),
                        subtitle: Text(
                          pendingRemovals.contains(rule['id'])
                              ? 'Удаление ожидает сверки с сервером. Потяните список вниз после подключения.'
                              : '${rule['message']}\n${rule['enabled'] == true ? 'За ${rule['minutes_before']} мин.' : 'Выключено'}',
                        ),
                        onTap:
                            interactionOpen ||
                                pendingRemovals.contains(rule['id'])
                            ? null
                            : () => edit(context, rule),
                        trailing: IconButton(
                          tooltip: 'Удалить правило',
                          icon: const Icon(Icons.delete_outline),
                          onPressed:
                              interactionOpen ||
                                  pendingRemovals.contains(rule['id'])
                              ? null
                              : () => remove(context, rule),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: interactionOpen ? null : () => edit(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить правило'),
                  ),
                ],
              ),
            ),
    ),
  );
}
