import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'activity_lists.dart';
import 'forms.dart';
import 'family_action.dart';
import 'form_layout.dart';
import 'child_visuals.dart';
import 'visuals.dart';
import 'repository.dart';
import 'schedule.dart';
import 'design_system.dart';

class MoneyScreen extends StatefulWidget {
  final FamilyRepository repository;
  final Future<void> Function(Future<Map<String, dynamic>> Function()) perform;
  const MoneyScreen({
    super.key,
    required this.repository,
    required this.perform,
  });

  @override
  State<MoneyScreen> createState() => _MoneyScreenState();
}

enum _MoneyDecision { penalty, payout }

class _MoneyScreenState extends State<MoneyScreen> {
  FamilyRepository get repository => widget.repository;
  Future<void> Function(Future<Map<String, dynamic>> Function()) get perform =>
      widget.perform;
  final authentication = LocalAuthentication();
  bool confirming = false, authenticating = false, cancelRequested = false;
  bool _formOpen = false;
  FamilyActionAccess? _activeFormAccess;
  FamilyActionAccess? _viewAccess;

  Map<String, dynamic>? penaltyTask(
    FamilyRepository owner,
    Map<String, dynamic> penalty,
  ) => penalty['source_type'] != 'task'
      ? null
      : owner
            .rows('tasks')
            .where((t) => t['id'] == penalty['source_id'])
            .firstOrNull;

  String? penaltyOccurrence(
    FamilyRepository owner,
    Map<String, dynamic> penalty,
  ) {
    final task = penaltyTask(owner, penalty);
    if (task == null) return null;
    return taskCalendarTimeText(owner.snapshot, task) ??
        'Срок: ${familyDateTimeText(owner.snapshot, task['due_at'] as String)}';
  }

  @override
  void initState() {
    super.initState();
    repository.addListener(observeViewAccess);
  }

  void observeViewAccess() {
    // Keep a temporary loss of access observable even between two builds.
    final access = _viewAccess;
    if (access != null && !access.valid) access.invalidate();
  }

  FamilyActionAccess captureViewAccess() {
    final owner = repository;
    if (_viewAccess == null || !_viewAccess!.valid) {
      _viewAccess?.dispose();
      _viewAccess = FamilyActionAccess(
        owner,
        permitted: () =>
            mounted && identical(repository, owner) && owner.role != 'relative',
      );
    }
    return _viewAccess!;
  }

  Future<void> runQuickAction(
    BuildContext context,
    FamilyActionAccess access,
    Future<Map<String, dynamic>> Function(FamilyRepository owner) action,
  ) async {
    if (!viewCurrent(context, access)) return;
    await perform(() {
      if (!viewCurrent(context, access)) {
        throw ApiFailure(
          409,
          'Семейный доступ изменился. Откройте раздел заново.',
        );
      }
      return action(access.repository);
    });
  }

  bool viewCurrent(BuildContext context, FamilyActionAccess access) =>
      mounted &&
      context.mounted &&
      access.valid &&
      ModalRoute.of(context)?.isCurrent == true;

  Future<void> runViewInteraction(
    BuildContext context,
    FamilyActionAccess access,
    Future<dynamic> Function() action,
  ) async {
    if (!viewCurrent(context, access)) return;
    await action();
  }

  Future<Map<String, dynamic>?> moneyForm(
    BuildContext context,
    String title,
    List<FamilyField> fields, {
    required String role,
    required Future<dynamic> Function(
      FamilyRepository owner,
      Map<String, dynamic> values,
    )
    onSave,
  }) async {
    if (_formOpen || !mounted) return null;
    final owner = repository;
    final access = FamilyActionAccess(
      owner,
      permitted: () =>
          mounted && identical(repository, owner) && owner.role == role,
    );
    if (!access.valid) {
      access.dispose();
      return null;
    }
    _formOpen = true;
    _activeFormAccess = access;
    try {
      return await familyForm(
        context,
        title,
        fields,
        access: access,
        onSave: (values) {
          access.requireCurrent();
          return onSave(owner, values);
        },
      );
    } finally {
      _formOpen = false;
      _activeFormAccess = null;
      access.dispose();
    }
  }

  void cancelAuthentication() {
    if (!authenticating || cancelRequested) return;
    cancelRequested = true;
    unawaited(
      authentication.stopAuthentication().catchError((Object _) => false),
    );
  }

  @override
  void didUpdateWidget(covariant MoneyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, repository)) {
      oldWidget.repository.removeListener(observeViewAccess);
      repository.addListener(observeViewAccess);
      _viewAccess?.invalidate();
      cancelAuthentication();
      _activeFormAccess?.invalidate();
    }
  }

  @override
  void dispose() {
    repository.removeListener(observeViewAccess);
    _viewAccess?.dispose();
    _activeFormAccess?.invalidate();
    cancelAuthentication();
    super.dispose();
  }

  Future<void> requestReward(
    BuildContext context,
    Map<String, dynamic> reward,
    FamilyActionAccess access,
  ) async {
    final position = Scrollable.maybeOf(context)?.position;
    var saved = false;
    await runQuickAction(context, access, (owner) async {
      final result = await owner.mutate('/v1/redemptions', {
        'reward_id': reward['id'],
        'expected_price': reward['price'],
      });
      saved = access.valid;
      return result;
    });
    if (context.mounted &&
        saved &&
        viewCurrent(context, access) &&
        gameDesign.value != null &&
        position != null &&
        position.hasPixels) {
      // Show the changed available/reserved balance, as in the approved
      // request state. A failed request keeps the selected reward in view.
      position.jumpTo(0);
    }
  }

  Future<void> confirmMoney(
    BuildContext context,
    _MoneyDecision decision,
    Map<String, dynamic> record,
    String title,
    String explanation,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    if (confirming || !mounted || !context.mounted) return;
    final owner = repository;
    final identity = (
      owner.endpoint,
      owner.sessionTag,
      owner.generation,
      owner.userId,
    );
    final shown = Map<String, dynamic>.from(record);
    final shownOccurrence = decision == _MoneyDecision.penalty
        ? penaltyOccurrence(owner, shown)
        : null;
    var invalidated = false;
    bool owns() =>
        mounted &&
        identical(repository, owner) &&
        owner.signedIn &&
        owner.role == 'parent' &&
        (owner.endpoint, owner.sessionTag, owner.generation, owner.userId) ==
            identity;
    bool current() {
      if (invalidated || !owns() || !owner.online) return false;
      final row = owner
          .rows(
            decision == _MoneyDecision.penalty ? 'penalties' : 'redemptions',
          )
          .where((item) => item['id'] == shown['id'])
          .firstOrNull;
      if (row == null || row['amount'] != shown['amount']) return false;
      return decision == _MoneyDecision.penalty
          ? row['status'] == 'pending' &&
                row['reason'] == shown['reason'] &&
                row['source_type'] == shown['source_type'] &&
                row['source_id'] == shown['source_id'] &&
                row['source_version'] == shown['source_version'] &&
                (row['source_type'] != 'task' ||
                    penaltyTask(owner, row) != null) &&
                penaltyOccurrence(owner, row) == shownOccurrence
          : row['status'] == 'claimed' &&
                row['claimed_by'] == owner.userId &&
                row['title'] == shown['title'];
    }

    if (!current()) return;
    final route = ModalRoute.of(context);
    bool canSend() =>
        context.mounted && current() && (route == null || route.isCurrent);
    void changed() {
      if (!current()) {
        invalidated = true;
        cancelAuthentication();
      }
    }

    confirming = true;
    cancelRequested = false;
    owner.addListener(changed);
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (_) => _MoneyConsent(
          repository: owner,
          owns: owns,
          current: current,
          title: title,
          explanation: explanation,
        ),
      );
      if (approved != true || !canSend()) return;
      await perform(() async {
        if (!canSend()) {
          throw ApiFailure(
            409,
            'Подтверждение устарело. Откройте действие заново.',
          );
        }
        bool authenticated;
        authenticating = true;
        try {
          authenticated = await authentication.authenticate(
            localizedReason: 'Подтвердите семейное финансовое действие',
          );
        } on LocalAuthException catch (error) {
          final message = switch (error.code) {
            LocalAuthExceptionCode.userCanceled ||
            LocalAuthExceptionCode.systemCanceled =>
              'Подтверждение устройства отменено',
            LocalAuthExceptionCode.noCredentialsSet ||
            LocalAuthExceptionCode.noBiometricsEnrolled => 'Настройте PIN-код, пароль или рисунок блокировки в настройках устройства и повторите подтверждение.',
            LocalAuthExceptionCode.temporaryLockout ||
            LocalAuthExceptionCode.biometricLockout => 'Подтверждение устройства временно заблокировано. Разблокируйте его обычным способом и попробуйте снова.',
            LocalAuthExceptionCode.authInProgress => 'Подтверждение устройства уже открыто. Завершите его и попробуйте снова.',
            _ => 'Не удалось подтвердить действие на устройстве. Проверьте настройки блокировки экрана и попробуйте снова.',
          };
          throw ApiFailure(403, message);
        } on PlatformException {
          throw ApiFailure(
            403,
            'Не удалось подтвердить действие на устройстве. Проверьте настройки блокировки экрана и попробуйте снова.',
          );
        } finally {
          authenticating = false;
        }
        if (!canSend()) {
          throw ApiFailure(
            409,
            'Подтверждение устарело. Откройте действие заново.',
          );
        }
        if (!authenticated) {
          throw ApiFailure(403, 'Подтверждение устройства отменено');
        }
        return action();
      });
    } finally {
      owner.removeListener(changed);
      confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = repository;
    final viewAccess = captureViewAccess();
    if (repo.role == 'relative') return const SizedBox.shrink();
    final balance = repo.snapshot!['balance'];
    final penalties = repo
        .rows('penalties')
        .where((p) => p['status'] == 'pending')
        .toList();
    final rewards = repo
        .rows('rewards')
        .where((r) => repo.role == 'parent' || r['available'] == 1)
        .toList();
    final redemptions = repo.rows('redemptions').reversed.toList();
    final ledger = repo.rows('ledger').reversed.toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: spacedFormItems([
        if (repo.role == 'child')
          const ChildHeader(
            art: 2,
            title: 'Копилка желаний',
            message: 'Выбирай награду, копи монеты и радуйся своим успехам!',
          ),
        Text(
          repo.role == 'child' ? 'Мои монеты' : 'Семейные монеты',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text('1 монета = 1 рубль. Деньги выдаёт родитель.'),
        if (repo.role == 'child')
          Card(
            color: warmYellow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const FamilyIcon(3, size: 64),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (balance['available'] as num) < 0
                              ? 'Твой баланс монет'
                              : 'Доступно для твоих желаний',
                        ),
                        Text(
                          '${balance['available']}',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Всего: ${balance['total']} · в заявках: ${balance['reserved']}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (repo.role != 'child')
          Text(
            'Всего: ${balance['total']} · в заявках: ${balance['reserved']} · доступно: ${balance['available']}',
          ),
        if (!repo.online)
          const Text(
            'Последний сохранённый баланс. Обмен доступен после подключения.',
          ),
        if ((balance['available'] as num) < 0)
          const Text(
            'Баланс отрицательный. Монеты за выполненные задания и оценки будут уменьшать минус. Новые награды и выдача денег доступны, когда монет снова достаточно.',
          ),
        if (repo.role == 'child')
          FilledButton(
            onPressed: (balance['available'] as num) <= 0
                ? null
                : () async {
                    if (!viewCurrent(context, viewAccess)) return;
                    final form = await moneyForm(
                      context,
                      'Попросить выдачу денег',
                      [
                        const FamilyField(
                          'amount',
                          'Сколько рублей',
                          kind: 'int',
                          initial: 1,
                        ),
                      ],
                      role: 'child',
                      onSave: (owner, values) =>
                          owner.mutate('/v1/redemptions', values),
                    );
                    if (form == null) return;
                  },
            child: const Text('Обменять монеты на рубли'),
          ),
        if (repo.role == 'parent') ...[
          OutlinedButton(
            onPressed: () async {
              if (!viewCurrent(context, viewAccess)) return;
              final rules = {
                for (final r in repo.rows('grade_rules'))
                  r['grade'].toString(): r['amount'],
              };
              final form = await moneyForm(
                context,
                'Монеты за оценки',
                [
                  for (final grade in ['5', '4', '3', '2'])
                    FamilyField(
                      grade,
                      'За оценку $grade (минус — штраф)',
                      kind: 'signed',
                      initial: rules[grade] ?? 0,
                    ),
                ],
                role: 'parent',
                onSave: (owner, values) => owner.mutate('/v1/grade-rules', {
                  'amounts': values,
                }, method: 'PUT'),
              );
              if (form == null) return;
            },
            child: const Text('Настроить суммы за оценки'),
          ),
          OutlinedButton(
            onPressed: () => runViewInteraction(
              context,
              viewAccess,
              () => editReward(context),
            ),
            child: const Text('Добавить награду'),
          ),
          Text(
            'Штрафы ждут подтверждения: ${penalties.length}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (penalties.isEmpty) const Text('Неподтверждённых штрафов нет'),
          ActivityWindow(
            key: const ValueKey('money-penalties'),
            count: penalties.length,
            filterKey: (repo.sessionTag, repo.generation),
            compactWhenShort: true,
            showCount: false,
            emptyText: '',
            itemBuilder: (context, index) {
              final penalty = penalties[index];
              final occurrence = penaltyOccurrence(repo, penalty);
              final sourceAvailable =
                  penalty['source_type'] != 'task' || occurrence != null;
              return Card(
                key: ValueKey('penalty-${penalty['id']}'),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        penalty['reason'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (occurrence != null) Text(occurrence),
                      if (!sourceAvailable)
                        const Text(
                          'Дата и время задания недоступны. Обновите данные перед подтверждением.',
                        ),
                      const SizedBox(height: 8),
                      Text('Назначено: ${penalty['amount']} монет'),
                      Text(
                        'При подтверждении спишется: ${penalty['amount']} монет. Баланс может стать отрицательным.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: !sourceAvailable
                                ? null
                                : () => runViewInteraction(
                                    context,
                                    viewAccess,
                                    () => confirmMoney(
                                      context,
                                      _MoneyDecision.penalty,
                                      penalty,
                                      'Штраф: ${penalty['amount']} монет',
                                      '${penalty['reason']}\n${occurrence == null ? '' : '$occurrence\n'}Спишется вся сумма: ${penalty['amount']} монет, даже при нулевом балансе. Баланс может стать отрицательным.',
                                      () => repo.mutate(
                                        '/v1/penalties/${penalty['id']}/approve',
                                        {},
                                      ),
                                    ),
                                  ),
                            child: const Text('Применить'),
                          ),
                          OutlinedButton(
                            onPressed: () => runQuickAction(
                              context,
                              viewAccess,
                              (owner) => owner.mutate(
                                '/v1/penalties/${penalty['id']}/waive',
                                {},
                              ),
                            ),
                            child: const Text('Отменить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
        Text(
          'Награды и цель накопления',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (repo.role == 'parent' && rewards.isEmpty)
          const Text('Наград пока нет. Добавьте первую награду для ребёнка.'),
        if (repo.role == 'child' &&
            repo.rows('rewards').where((r) => r['available'] == 1).isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Попроси семью добавить награду, на которую тебе хочется копить.',
              ),
            ),
          ),
        ActivityWindow(
          key: const ValueKey('money-rewards'),
          count: rewards.length,
          filterKey: (repo.sessionTag, repo.generation),
          compactWhenShort: true,
          showCount: false,
          emptyText: '',
          itemBuilder: (context, index) {
            final reward = rewards[index];
            return ExpansionTile(
              key: ValueKey('reward-${reward['id']}'),
              initiallyExpanded:
                  repo.role == 'child' &&
                  repo.snapshot?['goal']?['reward_id'] == reward['id'],
              leading: repo.role == 'child'
                  ? const ChildArt(2, size: 50)
                  : null,
              title: Text('${reward['title']} · ${reward['price']} монет'),
              subtitle: Text(
                repo.snapshot?['goal']?['reward_id'] == reward['id']
                    ? 'Моя цель накопления'
                    : reward['description'] as String,
              ),
              children: [
                if (repo.role == 'child' &&
                    repo.snapshot?['goal']?['reward_id'] == reward['id'])
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          minHeight: 12,
                          borderRadius: BorderRadius.circular(12),
                          value: (reward['price'] as num) <= 0
                              ? 1
                              : ((balance['available'] as num) /
                                        (reward['price'] as num))
                                    .clamp(0.0, 1.0)
                                    .toDouble(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (balance['available'] as num) >=
                                  (reward['price'] as num)
                              ? 'На эту награду уже хватает! Можно отправить заявку.'
                              : 'До цели ещё ${(reward['price'] as num) - (balance['available'] as num)} монет',
                        ),
                      ],
                    ),
                  ),
                if (repo.role == 'parent') ...[
                  TextButton(
                    onPressed: () => runViewInteraction(
                      context,
                      viewAccess,
                      () => editReward(context, reward),
                    ),
                    child: const Text('Изменить награду'),
                  ),
                  TextButton(
                    onPressed: () => runViewInteraction(
                      context,
                      viewAccess,
                      () => deleteReward(context, reward['id'] as String),
                    ),
                    child: const Text('Удалить награду'),
                  ),
                ],
                if (repo.role == 'child')
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => runQuickAction(
                          context,
                          viewAccess,
                          (owner) => owner.mutate('/v1/goal', {
                            'reward_id': reward['id'],
                          }, method: 'PUT'),
                        ),
                        child: const Text('Копить на это'),
                      ),
                      FilledButton(
                        onPressed:
                            (balance['available'] as num) <
                                (reward['price'] as num)
                            ? null
                            : () => runViewInteraction(
                                context,
                                viewAccess,
                                () =>
                                    requestReward(context, reward, viewAccess),
                              ),
                        child: const Text('Попросить награду'),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
        Text(
          repo.role == 'child' ? 'Мои просьбы' : 'Заявки на выдачу',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (redemptions.isEmpty) const Text('Заявок пока нет'),
        ActivityWindow(
          key: const ValueKey('money-requests'),
          count: redemptions.length,
          filterKey: (repo.sessionTag, repo.generation),
          compactWhenShort: true,
          showCount: false,
          emptyText: '',
          itemBuilder: (context, index) {
            final request = redemptions[index];
            return ExpansionTile(
              key: ValueKey('redemption-${request['id']}'),
              title: Text('${request['title']} · ${request['amount']}'),
              subtitle: Text(statusText(request['status'] as String)),
              children: [
                if (repo.role == 'child' && request['status'] == 'pending')
                  TextButton(
                    onPressed: () => runQuickAction(
                      context,
                      viewAccess,
                      (owner) => owner.mutate(
                        '/v1/redemptions/${request['id']}/actions',
                        {'action': 'cancel'},
                      ),
                    ),
                    child: const Text('Отменить заявку'),
                  ),
                if (repo.role == 'parent' && request['status'] == 'pending')
                  FilledButton(
                    onPressed: () => runQuickAction(
                      context,
                      viewAccess,
                      (owner) => owner.mutate(
                        '/v1/redemptions/${request['id']}/actions',
                        {'action': 'claim'},
                      ),
                    ),
                    child: const Text('Взять для выдачи'),
                  ),
                if (repo.role == 'parent' &&
                    request['status'] == 'claimed' &&
                    request['claimed_by'] == repo.userId) ...[
                  const Text(
                    'После передачи денег подтвердите выдачу. При обрыве связи сверяйте эту заявку; повторно деньги не выдавайте.',
                  ),
                  FilledButton(
                    onPressed: () => runViewInteraction(
                      context,
                      viewAccess,
                      () => confirmMoney(
                        context,
                        _MoneyDecision.payout,
                        request,
                        'Подтвердить фактическую выдачу',
                        'Ребёнок: ${repo.rows('members').where((m) => m['role'] == 'child').firstOrNull?['name'] ?? ''}\n${request['title']}\nСумма: ${request['amount']} монет. Деньги или награда уже переданы ребёнку?',
                        () => repo.mutate(
                          '/v1/redemptions/${request['id']}/actions',
                          {'action': 'confirm'},
                        ),
                      ),
                    ),
                    child: const Text('Уже выдал — подтвердить'),
                  ),
                  TextButton(
                    onPressed: () => runQuickAction(
                      context,
                      viewAccess,
                      (owner) => owner.mutate(
                        '/v1/redemptions/${request['id']}/actions',
                        {'action': 'release'},
                      ),
                    ),
                    child: const Text('Ещё не выдал — вернуть в ожидание'),
                  ),
                ],
                if (repo.role == 'parent' &&
                    (request['status'] == 'pending' ||
                        (request['status'] == 'claimed' &&
                            request['claimed_by'] == repo.userId)))
                  TextButton(
                    onPressed: () => runQuickAction(
                      context,
                      viewAccess,
                      (owner) => owner.mutate(
                        '/v1/redemptions/${request['id']}/actions',
                        {'action': 'reject'},
                      ),
                    ),
                    child: const Text('Отклонить до выдачи'),
                  ),
              ],
            );
          },
        ),
        Text('История монет', style: Theme.of(context).textTheme.titleLarge),
        if (ledger.isEmpty) const Text('Начислений и списаний пока нет'),
        ActivityWindow(
          key: const ValueKey('money-ledger'),
          count: ledger.length,
          filterKey: (repo.sessionTag, repo.generation),
          compactWhenShort: true,
          showCount: false,
          emptyText: '',
          itemBuilder: (context, index) {
            final entry = ledger[index];
            return ListTile(
              key: ValueKey('ledger-${entry['id']}'),
              title: Text('${entry['actual']} · ${entry['reason']}'),
              subtitle: Text(
                '${familyDateTimeText(repo.snapshot, entry['created_at'] as String)}${entry['requested'] != entry['actual'] ? ' · назначено ${entry['requested']}, применено ${entry['actual']}' : ''}',
              ),
            );
          },
        ),
      ]),
    );
  }

  Future<void> deleteReward(BuildContext context, String rewardId) async {
    if (_formOpen || !mounted) return;
    final repo = repository;
    final access = FamilyActionAccess(
      repo,
      permitted: () =>
          mounted && identical(repository, repo) && repo.role == 'parent',
    );
    if (!access.valid) {
      access.dispose();
      return;
    }
    final identity = repo.sessionTag, generation = repo.generation;
    Map<String, dynamic>? current() {
      if (!access.valid ||
          repo.sessionTag != identity ||
          repo.generation != generation ||
          repo.role != 'parent') {
        return null;
      }
      return repo
          .rows('rewards')
          .where((row) => row['id'] == rewardId)
          .firstOrNull;
    }

    final opened = current();
    if (opened == null) {
      access.dispose();
      return;
    }
    final revision = opened['revision'];
    _formOpen = true;
    _activeFormAccess = access;
    try {
      final confirmed = await showFamilyActionDialog<bool>(
        context: context,
        builder: (context) => FamilyActionDialog<bool>(
          access: access,
          builder: (context, close) => AnimatedBuilder(
            animation: repo,
            builder: (context, _) {
              final reward = current();
              return AlertDialog(
                scrollable: true,
                title: const Text('Удалить награду?'),
                content: Text(
                  reward == null
                      ? 'Награда уже удалена или доступ изменился'
                      : '${reward['title']} · ${reward['price']} монет\nНаграда исчезнет из списка. Уже отправленные заявки сохранят прежнюю стоимость.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => close(null),
                    child: const Text('Отмена'),
                  ),
                  FilledButton(
                    onPressed: reward == null ? null : () => close(true),
                    child: const Text('Удалить'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      if (confirmed != true || current() == null) return;
      await perform(() {
        access.requireCurrent();
        return repo.mutate('/v1/rewards/$rewardId', {
          'expected_revision': ?revision,
        }, method: 'DELETE');
      });
    } finally {
      _formOpen = false;
      _activeFormAccess = null;
      access.dispose();
    }
  }

  Future<void> editReward(
    BuildContext context, [
    Map<String, dynamic>? reward,
  ]) async {
    final revision = reward?['revision'];
    final form = await moneyForm(
      context,
      'Семейная награда',
      [
        FamilyField('title', 'Название', initial: reward?['title']),
        FamilyField(
          'description',
          'Описание',
          kind: 'note',
          required: false,
          initial: reward?['description'],
        ),
        FamilyField(
          'price',
          'Стоимость в монетах',
          kind: 'int',
          initial: reward?['price'] ?? 1,
        ),
        FamilyField(
          'available',
          'Показывать ребёнку',
          kind: 'bool',
          initial: reward == null || reward['available'] == 1,
        ),
      ],
      role: 'parent',
      onSave: (owner, values) => owner.mutate(
        '/v1/rewards${reward == null ? '' : '/${reward['id']}'}',
        {...values, 'expected_revision': ?revision},
        method: reward == null ? 'POST' : 'PUT',
      ),
    );
    if (form == null) return;
  }
}

class _MoneyConsent extends StatefulWidget {
  final FamilyRepository repository;
  final bool Function() owns, current;
  final String title, explanation;
  const _MoneyConsent({
    required this.repository,
    required this.owns,
    required this.current,
    required this.title,
    required this.explanation,
  });

  @override
  State<_MoneyConsent> createState() => _MoneyConsentState();
}

class _MoneyConsentState extends State<_MoneyConsent> {
  bool closing = false;
  void close(bool consent) {
    if (closing ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        (consent && !widget.current())) {
      return;
    }
    setState(() => closing = true);
    Navigator.pop(context, consent);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      final owns = widget.owns(), current = widget.current();
      return AlertDialog(
        scrollable: true,
        title: Text(current ? widget.title : 'Подтверждение недоступно'),
        content: Text(
          !owns
              ? 'Семейный доступ изменился. Закройте это окно.'
              : !widget.repository.online
              ? 'Нет подключения. Проверьте связь и откройте действие заново.'
              : !current
              ? 'Данные изменились. Обновите список и откройте действие заново.'
              : widget.explanation,
        ),
        actions: [
          TextButton(
            onPressed: closing ? null : () => close(false),
            child: Text(current ? 'Отмена' : 'Закрыть'),
          ),
          if (current)
            FilledButton(
              onPressed: closing ? null : () => close(true),
              child: const Text('Подтвердить'),
            ),
        ],
      );
    },
  );
}
