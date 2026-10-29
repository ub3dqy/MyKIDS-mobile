import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'design_system.dart';
import 'design_picker.dart';
import 'design_preferences.dart';

import 'background.dart';
import 'activity_lists.dart';
import 'call_permissions.dart';
import 'forms.dart';
import 'family_action.dart';
import 'form_layout.dart';
import 'engagement/engagement_entries.dart';
import 'engagement/engagement_scope.dart';
import 'invitation_dialog.dart';
import 'repository.dart';
import 'assistant_settings.dart';

class SettingsScreen extends StatefulWidget {
  final FamilyRepository repository;
  final BackgroundServices background;
  final String? initializationError;
  final Future<void> Function(Future<Map<String, dynamic>> Function()) perform;
  final Future<void> Function() onUpdates;
  final DesignPreferences? designPreferences;
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.background,
    required this.perform,
    required this.onUpdates,
    this.initializationError,
    this.designPreferences,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  FamilyRepository get repository => widget.repository;
  BackgroundServices get background => widget.background;
  bool editingQuietHours = false;
  FamilyActionAccess? quietHoursAccess;
  FamilyActionAccess? memberAccess;

  @override
  void initState() {
    super.initState();
    repository.addListener(observeMemberAccess);
  }

  void observeMemberAccess() {
    final access = memberAccess;
    if (access != null && !access.valid) access.invalidate();
    if (mounted) setState(() {});
  }

  FamilyActionAccess captureMemberAccess() {
    final owner = repository;
    if (memberAccess == null || !memberAccess!.valid) {
      memberAccess?.dispose();
      memberAccess = FamilyActionAccess(
        owner,
        permitted: () =>
            mounted && identical(repository, owner) && owner.role == 'parent',
      );
    }
    return memberAccess!;
  }

  bool memberViewCurrent(BuildContext context, FamilyActionAccess access) =>
      mounted &&
      context.mounted &&
      identical(repository, access.repository) &&
      access.valid &&
      ModalRoute.of(context)?.isCurrent == true;

  Future<void> changeMemberPermission(
    BuildContext context,
    FamilyActionAccess access,
    Map<String, dynamic> shown,
    String permission,
    bool value,
  ) async {
    final owner = access.repository;
    bool current() {
      if (!memberViewCurrent(context, access) || !owner.online) return false;
      final member = owner
          .rows('members')
          .where((m) => m['id'] == shown['id'])
          .firstOrNull;
      return member != null &&
          member['role'] == 'relative' &&
          shown['permissions_revision'] is String &&
          member['permissions_revision'] == shown['permissions_revision'] &&
          const [
            'active',
            'create_tasks',
            'view_tasks',
            'review_tasks',
          ].every((key) => member[key] == shown[key]);
    }

    if (!current()) return;
    await widget.perform(() async {
      if (!current()) {
        throw ApiFailure(409, 'Доступ изменился. Откройте настройки заново.');
      }
      final result = await owner.mutate('/v1/members/${shown['id']}', {
        permission: value,
        'expected_revision': shown['permissions_revision'],
      }, method: 'PATCH');
      if (!mounted || !context.mounted || !memberViewCurrent(context, access)) {
        throw ApiFailure(409, 'Доступ изменился. Откройте настройки заново.');
      }
      return result['queued'] == true
          ? result
          : {...result, 'message': 'Права доступа обновлены'};
    });
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, repository)) {
      oldWidget.repository.removeListener(observeMemberAccess);
      repository.addListener(observeMemberAccess);
      memberAccess?.invalidate();
      quietHoursAccess?.invalidate();
    }
  }

  @override
  void dispose() {
    repository.removeListener(observeMemberAccess);
    memberAccess?.dispose();
    quietHoursAccess?.invalidate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: spacedFormItems([
      if (gameDesign.value != null)
        GameScene(
          title: repository.role == 'child' ? 'Мой профиль' : 'Настройки семьи',
          description: 'Чтобы всё было удобно',
          compact: true,
        )
      else
        const Text('Настройки и семейный доступ'),
      DesignSettingsTile(
        preferences: widget.designPreferences ?? deviceDesignPreferences,
      ),
      if (EngagementScope.maybeOf(context) != null)
        const EngagementProfileEntries(),
      if (gameDesign.value != null && repository.role == 'child')
        ExpansionTile(
          title: const Text('Настройки телефона'),
          subtitle: const Text('Уведомления и звонки'),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: spacedFormItems(phoneSettings(context)),
              ),
            ),
          ],
        )
      else
        ...phoneSettings(context),
      if (repository.role == 'parent') ...[
        OutlinedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AssistantSettings(repository: repository),
            ),
          ),
          child: const Text('Настройки помощника'),
        ),
        OutlinedButton(
          onPressed: () => editQuietHours(context),
          child: const Text('Часовой пояс и тихие часы'),
        ),
        FamilyInvitations(repository: repository, perform: widget.perform),
        relativePermissions(),
        ActionHistory(repository: repository),
      ],
      _LogoutButton(repository: repository),
    ]),
  );

  Future<void> editQuietHours(BuildContext context) async {
    if (editingQuietHours || !mounted) return;
    final owner = repository;
    final access = FamilyActionAccess(
      owner,
      permitted: () =>
          mounted && identical(repository, owner) && owner.role == 'parent',
    );
    if (!access.valid) {
      access.dispose();
      return;
    }
    editingQuietHours = true;
    quietHoursAccess = access;
    try {
      final current = owner.snapshot!['family'];
      await familyForm(
        context,
        'Часовой пояс и тихие часы',
        [
          FamilyField(
            'timezone',
            'Часовой пояс',
            kind: 'choice',
            initial: current['timezone'],
            choices: const {
              'Europe/Moscow': 'Москва',
              'Europe/Amsterdam': 'Нидерланды',
              'Asia/Yekaterinburg': 'Екатеринбург',
              'Asia/Novosibirsk': 'Новосибирск',
            },
          ),
          for (final e in const {
            'quiet_start': 'Начало тихих часов',
            'quiet_end': 'Окончание тихих часов',
          }.entries)
            FamilyField(
              e.key,
              e.value,
              kind: 'time',
              initial: TimeOfDay(
                hour: int.parse(
                  (current[e.key] as String? ??
                          (e.key == 'quiet_start' ? '22:00' : '07:00'))
                      .split(':')[0],
                ),
                minute: int.parse(
                  (current[e.key] as String? ?? '00:00').split(':')[1],
                ),
              ),
            ),
        ],
        access: access,
        onSave: (values) {
          access.requireCurrent();
          final body = {...values};
          for (final key in ['quiet_start', 'quiet_end']) {
            final t = body[key] as TimeOfDay;
            body[key] =
                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
          }
          return owner.mutate('/v1/family', body, method: 'PUT');
        },
      );
    } finally {
      editingQuietHours = false;
      quietHoursAccess = null;
      access.dispose();
    }
  }

  Future<void> openPhoneSettings(BuildContext context, String method) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Настройки телефона доступны в Android-приложении.'),
        ),
      );
      return;
    }
    try {
      await nativeCalls.invokeMethod(method);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось открыть настройки. Откройте их на телефоне: Приложения → MyKIDS.',
          ),
        ),
      );
    }
  }

  List<Widget> phoneSettings(BuildContext context) => [
    CallPermissionNotice(background: background, details: true),

    OutlinedButton(
      onPressed: widget.onUpdates,
      child: const Text('Проверить обновления приложения'),
    ),
    if (widget.initializationError != null) Text(widget.initializationError!),
    Text(
      background.pushReady
          ? 'Доставка уведомлений подключена; работа на телефоне требует проверки'
          : 'Сообщения при закрытом приложении и входящие звонки ещё требуют подключения уведомлений',
    ),
    const Text(
      'Напоминания о делах: по умолчанию за 30 минут. Время меняется у каждого события. '
      'В тихие часы напоминания не подаются. Телефон может задержать уведомление в режиме энергосбережжения.',
    ),
    OutlinedButton(
      onPressed: () => widget.perform(() async {
        await background.enableNotifications();
        await background.reminders();
        return {'message': 'Разрешения уведомлений запрошены'};
      }),
      child: const Text('Включить уведомления'),
    ),
    OutlinedButton(
      onPressed: () async {
        await openPhoneSettings(context, 'notificationSettings');
      },
      child: const Text('Настройки уведомлений телефона'),
    ),
    OutlinedButton(
      onPressed: () async {
        await openPhoneSettings(context, 'batterySettings');
      },
      child: const Text('Настройки работы в фоне'),
    ),
    OutlinedButton(
      onPressed: () async {
        await openPhoneSettings(context, 'fullScreenSettings');
      },
      child: const Text('Показ входящих звонков на экране'),
    ),
    if (background.callsNotificationsReady == false)
      const Text(
        'Входящие звонки не смогут появиться: разрешите уведомления MyKIDS в настройках телефона.',
      ),
    if (background.callsFullScreenReady == false)
      const Text(
        'Для звонков на заблокированном экране включите «Показ входящих звонков на экране».',
      ),
    if (!background.exactNotificationsReady)
      const Text(
        'Чтобы напоминания приходили в выбранное время, разрешите будильники и напоминания: нажмите «Включить уведомления».',
      ),
  ];

  Widget relativePermissions() {
    final access = captureMemberAccess();
    final members = repository
        .rows('members')
        .where((m) => m['role'] == 'relative')
        .toList();
    if (members.isEmpty) return const SizedBox.shrink();
    return ActivityWindow(
      key: const ValueKey('relative-permissions'),
      count: members.length,
      filterKey: (repository.sessionTag, repository.generation),
      compactWhenShort: true,
      showCount: false,
      emptyText: '',
      itemBuilder: (_, index) {
        final member = Map<String, dynamic>.unmodifiable(members[index]);
        final ready =
            repository.online && member['permissions_revision'] is String;
        return ExpansionTile(
          key: ValueKey('member-${member['id']}'),
          title: Text(member['name'] as String),
          subtitle: Text(
            member['active'] == 1 ? 'Доступ включён' : 'Доступ отключён',
          ),
          children: [
            if (!ready)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Подключитесь к интернету и обновите данные, чтобы изменить права доступа.',
                ),
              ),
            for (final permission in const {
              'create_tasks': 'Создавать задания',
              'view_tasks': 'Смотреть свои задания',
              'review_tasks': 'Проверять свои задания',
              'active': 'Доступ к семье',
            }.entries)
              SwitchListTile(
                title: Text(permission.value),
                value: member[permission.key] == 1,
                onChanged: !ready
                    ? null
                    : (value) => changeMemberPermission(
                        context,
                        access,
                        member,
                        permission.key,
                        value,
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _LogoutButton extends StatefulWidget {
  final FamilyRepository repository;
  const _LogoutButton({required this.repository});

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool leaving = false;

  Future<void> logout() async {
    if (leaving) return;
    setState(() => leaving = true);
    final repo = widget.repository;
    final messenger = ScaffoldMessenger.of(context);
    final epoch = repo.generation + 1;
    try {
      // Account removal must succeed independently of Android's notification
      // service. Cleanup is attempted only for the still signed-out identity.
      await repo.logout();
      if (kIsWeb || repo.signedIn || repo.generation != epoch) return;
      try {
        await repo.guardDeviceUpdate(() async {
          if (repo.signedIn || repo.generation != epoch) return;
          await notifications.cancelAll().timeout(const Duration(seconds: 3));
        });
      } catch (_) {
        if (messenger.mounted && !repo.signedIn && repo.generation == epoch) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Вы вышли из аккаунта. Не удалось убрать старые уведомления. Проверьте настройки телефона.',
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (messenger.mounted && repo.generation == epoch) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось полностью удалить данные. Попробуйте выйти ещё раз.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: leaving ? null : logout,
    child: Text(leaving ? 'Выходим…' : 'Выйти и удалить данные с телефона'),
  );
}
