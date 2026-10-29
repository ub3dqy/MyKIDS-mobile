import 'dart:async';

import 'design_system.dart';
import 'design_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/timezone.dart' as tz;

import 'background.dart';
import 'activity_lists.dart';
import 'assistant_rules.dart';
import 'calendar.dart';
import 'calendar_screen.dart';
import 'call_permissions.dart';
import 'child_rewards.dart';
import 'child_today.dart';
import 'child_visuals.dart';
import 'family_screen.dart';
import 'incoming_calls.dart';
import 'login_screen.dart';
import 'money_screen.dart';
import 'morning.dart';
import 'repository.dart';
import 'role_screen.dart';
import 'schedule.dart';
import 'settings_screen.dart';
import 'task_screen.dart';
import 'task_summary.dart';
import 'task_rules.dart';
import 'updates.dart';
import 'visuals.dart';
import 'engagement/engagement_scope.dart';
import 'engagement/production_controller.dart';
import 'engagement/production_photos.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = FamilyRepository();
  await Future.wait([
    deviceDesignPreferences.load(),
    repo.initialize(),
    precacheRasterArtwork(GameDesign.all.map((design) => design.animation)),
  ]);
  runApp(MyKidsApp(repository: repo));
}

class MyKidsApp extends StatefulWidget {
  final FamilyRepository repository;
  final AppUpdates Function() createUpdates;
  final BackgroundServices Function(FamilyRepository) createBackground;
  final DateTime Function() now;
  final Widget Function(BuildContext, Widget)? presentation;
  final GlobalKey<NavigatorState>? navigationKey;
  final ValueNotifier<int>? pageSelection;
  final DesignPreferences? designPreferences;
  const MyKidsApp({
    super.key,
    required this.repository,
    this.createUpdates = AppUpdates.new,
    this.createBackground = BackgroundServices.new,
    this.now = DateTime.now,
    this.presentation,
    this.navigationKey,
    this.pageSelection,
    this.designPreferences,
  });
  @override
  State<MyKidsApp> createState() => _MyKidsAppState();
}

class _MyKidsAppState extends State<MyKidsApp> with WidgetsBindingObserver {
  late final BackgroundServices background;
  late final navigatorKey = widget.navigationKey ?? GlobalKey<NavigatorState>();
  final callNavigation = FamilyCallNavigation();
  Timer? timer;
  int page = 0;
  bool busy = false;
  String? initializationError;
  bool showingUpdate = false;
  Future<UpdateOffer?>? updateCheck;
  DateTime? lastUpdateCheck;
  int? offeredUpdate;
  final childRewards = ChildRewardTracker();
  int pendingCoins = 0;
  bool pendingApproval = false;
  bool showingSuccess = false;
  bool showingMorning = false;
  bool checkingMorning = false;
  DateTime? calendarFocus;
  String calendarMode = 'День';
  late (String, String, int) calendarSession;
  FamilyRepository get repo => widget.repository;
  late final engagement = ProductionEngagementController(
    repo,
    selectPhotos: (task) async {
      final context = navigatorKey.currentState?.overlay?.context;
      if (!mounted || context == null || !context.mounted) return null;
      return choosePlayPhotos(context, task);
    },
    showDetailedReview: (id) async {
      final context = navigatorKey.currentState?.overlay?.context;
      if (!mounted || context == null || !context.mounted) return;
      await openTaskReview(
        context,
        repo,
        (action) => perform(context, action),
        id,
      );
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    calendarSession = (repo.endpoint, repo.sessionTag, repo.generation);
    calendarFocus = repo.calendarPosition?.day;
    calendarMode = repo.calendarPosition?.mode ?? 'День';
    repo.addListener(changed);
    gameDesign.addListener(designChanged);
    widget.pageSelection?.addListener(externalPageChanged);
    childRewards.observe(repo.snapshot);
    background = widget.createBackground(repo);
    unawaited(initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) => checkUpdates());
  }

  void externalPageChanged() {
    if (mounted) setState(() => page = widget.pageSelection!.value.clamp(0, 5));
  }

  void designChanged() {
    if (mounted) setState(() {});
  }

  Future<void> initialize() async {
    // Notification permissions and push registration must not delay saved
    // commands or the first authenticated snapshot after a cold start.
    startTimer();
    unawaited(refresh());
    try {
      await background.initialize((payload) async {
        if (payload?.startsWith('answer-call:') == true) {
          final context = navigatorKey.currentContext;
          if (context != null && mounted && !callNavigation.inCall) {
            await openFamilyCall(context, repo, payload!.substring(12));
          }
          return;
        }
        if (mounted) {
          setState(() {
            final date = payload?.startsWith('calendar:') == true
                ? DateTime.tryParse(payload!.split('|').first.substring(9))
                : null;
            page = date == null ? 4 : 1;
            if (date != null) {
              calendarMode = 'День';
              calendarFocus = familyClock(
                repo.snapshot,
                DateTime.utc(date.year, date.month, date.day, 12),
              );
              persistCalendar();
            }
          });
        }
        unawaited(repo.sync());
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => initializationError =
              'Фоновые уведомления требуют настройки и проверки на телефоне',
        );
      }
    }
    if (!mounted) return;
    await refresh();
  }

  void changed() {
    if (!mounted) return;
    final session = (repo.endpoint, repo.sessionTag, repo.generation);
    if (calendarSession != session) {
      calendarSession = session;
      calendarFocus = null;
      calendarMode = 'День';
    }
    final earned = childRewards.observe(repo.snapshot);
    if (repo.signedIn && repo.role == 'child') {
      if (earned != null) {
        pendingCoins += earned.coins;
        pendingApproval = true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => showChildSuccess());
      WidgetsBinding.instance.addPostFrameCallback((_) => showMorning());
    } else {
      pendingCoins = 0;
      pendingApproval = false;
    }
    if (!repo.signedIn) {
      page = 0;
      unawaited(background.reminders().catchError((Object _) {}));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !repo.signedIn) {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
    setState(() {});
  }

  void persistCalendar() {
    final day = calendarFocus;
    if (day == null) return;
    final session = calendarSession;
    unawaited(
      repo.saveCalendarPosition(day, calendarMode).catchError((Object _) {
        final context = navigatorKey.currentState?.overlay?.context;
        if (mounted &&
            calendarSession == session &&
            context != null &&
            context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Не удалось запомнить дату календаря'),
            ),
          );
        }
      }),
    );
  }

  Future<void> showChildSuccess() async {
    final context = navigatorKey.currentState?.overlay?.context;
    if (!mounted ||
        !repo.signedIn ||
        repo.role != 'child' ||
        !pendingApproval ||
        showingSuccess ||
        showingUpdate ||
        showingMorning ||
        busy ||
        navigatorKey.currentState?.canPop() == true ||
        context == null ||
        !context.mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final coins = pendingCoins;
    pendingCoins = 0;
    pendingApproval = false;
    showingSuccess = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => ChildSuccessDialog(
          title: 'Твои старания заметили!',
          coins: coins,
          message: coins > 0
              ? 'Семья подтвердила награду. Монеты начислены!'
              : 'Семья подтвердила выполнение. Отличная работа!',
        ),
      );
    } finally {
      showingSuccess = false;
      if (mounted) unawaited(showChildSuccess());
    }
  }

  void startTimer() {
    timer?.cancel();
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

  Future<void> showMorning({bool manual = false}) async {
    final context = navigatorKey.currentState?.overlay?.context;
    if (checkingMorning ||
        showingMorning ||
        !mounted ||
        !repo.signedIn ||
        repo.role != 'child' ||
        repo.snapshot == null ||
        showingSuccess ||
        showingUpdate ||
        busy ||
        pendingApproval ||
        context == null ||
        !context.mounted ||
        navigatorKey.currentState?.canPop() == true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    checkingMorning = true;
    final identity = repo.sessionTag;
    final userId = repo.userId;
    final day = familyClock(repo.snapshot, widget.now());
    final key = 'morning:$userId';
    try {
      if (!manual) {
        if (day.hour >= 12 || day.hour < 5 || page != 0) return;
        if (await repo.storage.read(key: key) == dateOnly(day)) return;
      }
      if (!mounted ||
          repo.sessionTag != identity ||
          !repo.signedIn ||
          !context.mounted ||
          busy ||
          showingUpdate ||
          showingSuccess ||
          pendingApproval ||
          navigatorKey.currentState?.canPop() == true) {
        return;
      }
      showingMorning = true;
      await repo.storage.write(key: key, value: dateOnly(day));
      if (!mounted || repo.sessionTag != identity || !context.mounted) return;
      final allDay = await showDialog<bool>(
        context: context,
        builder: (_) => MorningOverview(
          preparations: assistantHints(
            repo.snapshot!,
            day,
          ).map((hint) => hint.message).toSet().toList(),
          entries: morningEntries(calendarDay(repo.snapshot!, day)),
          hasConflicts: calendarConflicts(calendarDay(repo.snapshot!, day))
              .isNotEmpty,
          dayLabel: '${day.day}.${day.month.toString().padLeft(2, '0')}',
          online: repo.online,
        ),
      );
      if (mounted && repo.sessionTag == identity && allDay == true) {
        setState(() {
          calendarFocus = day;
          calendarMode = 'День';
          page = 1;
          persistCalendar();
        });
      }
    } finally {
      checkingMorning = false;
      showingMorning = false;
      if (mounted) unawaited(showChildSuccess());
    }
  }

  Future<void> refresh({bool resumed = false}) async {
    final identity = repo.sessionTag, epoch = repo.generation;
    if (resumed) {
      await repo.reconnect();
    } else {
      await repo.sync();
    }
    if (!mounted || identity != repo.sessionTag || epoch != repo.generation) {
      return;
    }
    if (mounted) unawaited(showChildSuccess());
    if (mounted) unawaited(showMorning());
    if (repo.signedIn) {
      unawaited(background.registerDevice().catchError((_) {}));
      try {
        await background.reminders();
      } catch (_) {
        /* Permission state is shown in settings. */
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startTimer();
      unawaited(background.checkCallPermissions().catchError((_) {}));
      unawaited(refresh(resumed: true));
      unawaited(checkUpdates());
    } else {
      timer?.cancel();
    }
  }

  Future<UpdateOffer?> loadUpdate() async {
    final updates = widget.createUpdates();
    try {
      return await updates.check(repo.uri('/downloads/latest.json'), 'family');
    } finally {
      updates.dispose();
    }
  }

  Future<void> checkUpdates({bool manual = false}) async {
    if (!mounted || showingUpdate || showingSuccess || showingMorning) return;
    if (!manual &&
        (updateCheck != null ||
            navigatorKey.currentState?.canPop() == true ||
            (lastUpdateCheck != null &&
                DateTime.now().difference(lastUpdateCheck!) <
                    const Duration(minutes: 10)))) {
      return;
    }
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null || !context.mounted) return;
    lastUpdateCheck = DateTime.now();
    // A manual request can join the automatic check already in progress.
    final pending = updateCheck ??= loadUpdate();
    if (manual) {
      // The dialog subscribes on the next frame; handle an immediate failure
      // here too without changing the error delivered to the dialog.
      pending.ignore();
      showingUpdate = true;
      try {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => UpdateCheckDialog(check: pending),
        );
        try {
          final offer = await pending;
          if (offer != null) offeredUpdate = offer.versionCode;
        } catch (_) {
          // The manual dialog already showed the check failure.
        }
      } finally {
        showingUpdate = false;
        if (identical(updateCheck, pending)) updateCheck = null;
      }
      return;
    }
    bool ownsDialog = false;
    try {
      final offer = await pending;
      if (!mounted ||
          showingUpdate ||
          showingSuccess ||
          showingMorning ||
          navigatorKey.currentState?.canPop() == true ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      if (!context.mounted) return;
      if (offer != null && offeredUpdate != offer.versionCode) {
        offeredUpdate = offer.versionCode;
        showingUpdate = true;
        ownsDialog = true;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => UpdateDialog(offer: offer),
        );
      }
    } catch (_) {
      // Automatic checks stay quiet; a manual check displays its own result.
    } finally {
      if (identical(updateCheck, pending)) updateCheck = null;
      if (ownsDialog) showingUpdate = false;
    }
  }

  Future<void> perform(
    BuildContext context,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    if (busy) return;
    setState(() => busy = true);
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
                  : 'Не удалось выполнить действие. Проверьте соединение',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
      if (mounted) unawaited(showChildSuccess());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    engagement.dispose();
    background.dispose();
    repo.removeListener(changed);
    gameDesign.removeListener(designChanged);
    widget.pageSelection?.removeListener(externalPageChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [callNavigation],
    builder: (context, child) {
      final content = IncomingCallHost(
        repository: repo,
        navigatorKey: navigatorKey,
        navigation: callNavigation,
        child: child!,
      );
      // The approval entry injects its isolated controller through presentation.
      // The ordinary app always supplies its authenticated server-backed one.
      final presented =
          widget.presentation?.call(context, content) ??
          (repo.snapshot?['engagement'] is List && gameDesign.value != null
              ? EngagementScope(controller: engagement, child: content)
              : content);
      final media = MediaQuery.of(context);
      final scaler = media.textScaler;
      // The approved layouts use the user's scale uniformly, including headings.
      // Android's nonlinear scaling would otherwise change their line breaks.
      if (gameDesign.value != null && scaler is SystemTextScaler) {
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(scaler.textScaleFactor),
          ),
          child: presented,
        );
      }
      return presented;
    },
    title: 'MyKIDS',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('ru')],
    theme: familyTheme(repo.role == 'child'),
    home: Builder(
      builder: (context) {
        if (!repo.signedIn || repo.snapshot == null) {
          if (!repo.signedIn && repo.variant.isEmpty) {
            return RoleScreen(repository: repo);
          }
          return LoginScreen(
            repository: repo,
            onLogin: refresh,
            onUpdates: () => checkUpdates(manual: true),
          );
        }
        Future<void> run(Future<Map<String, dynamic>> Function() action) =>
            perform(context, action);
        final selectedCalendarDay = calendarFocus;
        final views = <Widget>[
          TodayScreen(
            repository: repo,
            now: widget.now(),
            openPage: (value) => setState(() => page = value),
            onOverview: () => showMorning(manual: true),
            onReviewTask: (id) => openTaskReview(context, repo, run, id),
          ),
          CalendarScreen(
            key: ValueKey(calendarSession),
            repository: repo,
            perform: run,
            initialDay: selectedCalendarDay == null
                ? null
                : tz.TZDateTime(
                    familyClock(repo.snapshot).location,
                    selectedCalendarDay.year,
                    selectedCalendarDay.month,
                    selectedCalendarDay.day,
                  ),
            initialMode: calendarMode,
            onSelectionChanged: (day, mode) => setState(() {
              calendarFocus = day;
              calendarMode = mode;
              persistCalendar();
            }),
            openTasks: (day) => openCalendarTasks(context, repo, run, day),
          ),
          TaskScreen(repository: repo, perform: run),
          MoneyScreen(repository: repo, perform: run),
          FamilyScreen(repository: repo, perform: run),
          SettingsScreen(
            repository: repo,
            background: background,
            initializationError: initializationError,
            perform: run,
            onUpdates: () => checkUpdates(manual: true),
            designPreferences: widget.designPreferences,
          ),
        ];
        return PopScope<void>(
          canPop: page == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && page != 0) setState(() => page = 0);
          },
          child: Scaffold(
            appBar: AppBar(
              title: repo.role == 'child'
                  ? Row(
                      children: [
                        const FamilyLogo(width: 96),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            repo.snapshot!['user']['name'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Text('MyKIDS · ${repo.snapshot!['user']['name']}'),
              actions: [
                IconButton(
                  tooltip: 'Настройки',
                  onPressed: () => setState(() => page = 5),
                  icon: const FamilyIcon(5),
                ),
                if (repo.role == 'child')
                  FamilyCoinButton(
                    amount:
                        (repo.snapshot?['balance']?['available'] as num? ?? 0)
                            .toInt(),
                    online: repo.online,
                    onPressed: () => setState(() => page = 3),
                  ),
              ],
            ),
            body: FamilyBackdrop(
              child: repo.role == 'child',
              content: Column(
                children: [
                  if (busy) const LinearProgressIndicator(),
                  if (gameDesign.value == null && page != 5)
                    CallPermissionNotice(background: background),
                  if (!repo.online)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        gameDesign.value != null && repo.role == 'child'
                            ? 'Нет интернета. Ты видишь сохранённые дела. Монеты обновятся, когда появится связь.'
                            : 'Нет связи. Данные сохранены на ${repo.snapshot!['server_time']}. Монеты требуют сверки с сервером.',
                      ),
                    ),
                  Expanded(child: views[page]),
                ],
              ),
            ),
            bottomNavigationBar: gameDesign.value != null
                ? GameNavigation(
                    selected: page,
                    showMoney: repo.role != 'relative',
                    onSelect: (value) => setState(() => page = value),
                  )
                : ColoredBox(
                    color: repo.role == 'child' ? ink : const Color(0xfff8fbfe),
                    child: SafeArea(
                      child: Row(
                        children: [
                          for (final entry in const {
                            0: 'Сегодня',
                            1: 'Календарь',
                            2: 'Задания',
                            3: 'Монеты',
                            4: 'Семья',
                          }.entries)
                            if (!(repo.role == 'relative' && entry.key == 3))
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: repo.role == 'child'
                                        ? (page == entry.key
                                              ? ink
                                              : Colors.white)
                                        : null,
                                    backgroundColor: page == entry.key
                                        ? (repo.role == 'child'
                                              ? warmYellow
                                              : paleBlue)
                                        : null,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () =>
                                      setState(() => page = entry.key),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FamilyIcon(entry.key),
                                      const SizedBox(height: 4),
                                      Text(
                                        entry.value,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: page == entry.key
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    ),
  );
}

class TodayScreen extends StatelessWidget {
  final FamilyRepository repository;
  final DateTime? now;
  final ValueChanged<int> openPage;
  final VoidCallback? onOverview;
  final ValueChanged<String>? onReviewTask;
  const TodayScreen({
    super.key,
    required this.repository,
    required this.openPage,
    this.now,
    this.onOverview,
    this.onReviewTask,
  });
  @override
  Widget build(BuildContext context) {
    final lessons = daySchedule(
      repository.rows('schedules'),
      repository.rows('schedule_exceptions'),
      familyClock(repository.snapshot),
    );
    final clock = familyClock(repository.snapshot);
    final tasks = repository
        .rows('tasks')
        .where(
          (t) => ['assigned', 'returned', 'submitted'].contains(t['status']),
        )
        .toList();
    if (repository.role == 'child') {
      return ChildToday(
        repository: repository,
        now: now,
        openPage: openPage,
        onOverview: onOverview,
      );
    }
    final isRelative = repository.role == 'relative';
    final reviewTasks =
        tasks
            .where(
              (task) =>
                  task['status'] == 'submitted' &&
                  canReviewTask(repository.snapshot!['user'], task),
            )
            .toList()
          ..sort(compareTaskTime);
    final balance = repository.snapshot?['balance']?['available'] ?? 0;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FamilyLogo(),
        const SizedBox(height: 8),
        Text(
          'Сегодня',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          '${clock.day.toString().padLeft(2, '0')}.${clock.month.toString().padLeft(2, '0')}.${clock.year}',
        ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        heading,
        const SizedBox(height: 16),
        if (!isRelative)
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
                        const Text('Доступные семейные монеты'),
                        Text(
                          '$balance',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        if (!repository.online)
                          const Text('Сохранённый баланс'),
                        TextButton(
                          onPressed: () => openPage(3),
                          child: const Text('Награды и накопления'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        FamilySection(
          title: 'Ждут внимания',
          icon: 2,
          children: [
            Text('Результатов на проверке: ${reviewTasks.length}'),
            if (reviewTasks.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .35,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final task in reviewTasks)
                      Padding(
                        key: ValueKey('today-review-card-${task['id']}'),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task['title'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              taskCompactTimeText(repository.snapshot, task),
                            ),
                            FilledButton.icon(
                              key: ValueKey('today-review-${task['id']}'),
                              onPressed: () => onReviewTask != null
                                  ? onReviewTask!(task['id'] as String)
                                  : openPage(2),
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Проверить результат'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (!isRelative)
              Text(
                'Заявок на награды и деньги: ${repository.rows('redemptions').where((r) => ['pending', 'claimed'].contains(r['status'])).length}',
              ),
            FilledButton(
              onPressed: () => openPage(2),
              child: const Text('Открыть задания'),
            ),
          ],
        ),
        FamilySection(
          title: 'Сегодня на занятиях',
          icon: 1,
          children: [
            ActivityWindow(
              key: const ValueKey('today-lessons'),
              count: lessons.length,
              filterKey: (repository.sessionTag, repository.generation),
              compactWhenShort: true,
              showCount: false,
              emptyText: '',
              itemBuilder: (context, index) {
                final lesson = lessons[index];
                return ListTile(
                  title: Text(lesson['title'] as String),
                  subtitle: Text(
                    '${lesson['start']} – ${lesson['end']} · ${lesson['place'] ?? ''}',
                  ),
                );
              },
            ),
            if (lessons.isEmpty) const Text('На сегодня занятий нет'),
            TextButton(
              onPressed: () => openPage(1),
              child: const Text('Всё расписание'),
            ),
          ],
        ),
        FamilySection(
          title: 'Задания и результаты',
          icon: 2,
          children: [
            TodayTaskList(repository: repository, onOpen: () => openPage(2)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => openPage(2),
              child: const Text('Открыть задания'),
            ),
          ],
        ),
        FamilySection(
          title: 'Поговори с семьёй',
          icon: 4,
          children: [
            const Text('Чаты, голосовые сообщения, аудио и видеозвонки'),
            TextButton(
              onPressed: () => openPage(4),
              child: const Text('Чаты и звонки'),
            ),
          ],
        ),
        FutureBuilder(
          future: repository.pending(),
          builder: (context, data) => !data.hasData || data.data!.isEmpty
              ? const SizedBox.shrink()
              : PendingActivities(
                  rows: data.data!,
                  filterKey: (repository.sessionTag, repository.generation),
                ),
        ),
      ],
    );
  }
}
