import 'package:flutter/material.dart';

import 'assistant_settings.dart';
import 'background.dart';
import 'call_view.dart';
import 'child_visuals.dart';
import 'design_review_repository.dart';
import 'design_review_control.dart';
import 'design_system.dart';
import 'event_editor.dart';
import 'incoming_calls.dart';
import 'main.dart' as family;
import 'messenger_widgets.dart';
import 'schedule.dart';
import 'school_screen.dart';
import 'updates.dart';

/// Standalone approval entry. The ordinary entry never creates this repository.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    DesignReviewControl.errors.add(details.exceptionAsString());
    previousErrorHandler?.call(details);
  };
  gameDesign.value =
      GameDesign.byId(
        Uri.base.queryParameters['design'] ??
            const String.fromEnvironment('MYKIDS_DESIGN'),
      ) ??
      GameDesign.all.first;
  runApp(const DesignReviewApp());
}

class ReviewBackground extends BackgroundServices {
  ReviewBackground(super.repository) {
    pushReady = true;
    exactNotificationsReady = true;
    callsNotificationsReady = true;
    callsFullScreenReady = true;
    callsAlertsReady = true;
    callsLockScreenReady = true;
    callsMicrophoneReady = true;
    callsCameraReady = true;
  }
  @override
  Future<void> initialize(void Function(String?) onTap) async {}
  @override
  void identityChanged() {}
  @override
  Future<void> checkCallPermissions() async {}
  @override
  Future<void> registerDevice() async {}
  @override
  Future<void> pendingIncoming() async {}
  @override
  Future<void> reminders() async {}
  @override
  Future<void> enableNotifications() async {}
}

class ReviewUpdates extends AppUpdates {
  @override
  Future<UpdateOffer?> check(Uri manifestUrl, String setupRole) async => null;
}

class DesignReviewApp extends StatefulWidget {
  final DesignReviewRepository? repository;
  const DesignReviewApp({super.key, this.repository});
  @override
  State<DesignReviewApp> createState() => _DesignReviewAppState();
}

class _DesignReviewAppState extends State<DesignReviewApp> {
  late final repo = widget.repository ?? DesignReviewRepository();
  final navigation = GlobalKey<NavigatorState>();
  final pages = ReviewPageSelection();
  final surface = GlobalKey();
  late final control = DesignReviewControl(
    repository: repo,
    navigation: navigation,
    surface: surface,
    pages: pages,
    action: select,
  );
  @override
  void initState() {
    super.initState();
    control.bind();
  }

  final externalControls = Uri.base.queryParameters['controls'] == 'off';
  late bool toolbarVisible = !externalControls;
  bool reducedMotion = false;
  double textScale = 1;

  @override
  void dispose() {
    if (widget.repository == null) {
      repo.client.close();
      repo.dispose();
    }
    if (identical(DesignReviewControl.current, control)) {
      DesignReviewControl.current = null;
    }
    pages.dispose();
    super.dispose();
  }

  void open(Widget page) => navigation.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => page),
  );
  void select(String action) {
    final context = navigation.currentState!.overlay!.context;
    switch (action) {
      case 'toolbar':
        setState(() => toolbarVisible = !toolbarVisible);
        break;
      case 'reset':
        navigation.currentState!.popUntil((r) => r.isFirst);
        ScaffoldMessenger.maybeOf(context)
          ?..clearSnackBars()
          ..removeCurrentSnackBar();
        setState(() {
          textScale = 1;
          reducedMotion = false;
        });
        repo.reset();
        break;
      case 'empty':
        navigation.currentState!.popUntil((r) => r.isFirst);
        repo.showEmpty();
        break;
      case 'offline':
        repo.setConnection(!repo.online);
        break;
      case 'negative':
        repo.showNegative();
        break;
      case 'motion':
        setState(() => reducedMotion = !reducedMotion);
        break;
      case 'large':
        setState(() => textScale = textScale == 1 ? 1.5 : 1);
        break;
      case 'login':
        navigation.currentState!.popUntil((r) => r.isFirst);
        repo.logout();
        break;
      case 'assistant':
        open(AssistantSettings(repository: repo));
        break;
      case 'school':
        open(
          SchoolScreen(
            repository: repo,
            perform: (action) async {
              await action();
            },
            initialDay: familyClock(repo.snapshot),
          ),
        );
        break;
      case 'event':
        open(
          CalendarEditor(
            snapshot: repo.snapshot!,
            day: familyClock(repo.snapshot),
            onSave: (data) => repo.mutate('/v1/schedules', data),
          ),
        );
        break;
      case 'call':
        open(const ReviewCallPage());
        break;
      case 'success':
        showDialog<void>(
          context: context,
          builder: (_) => const ChildSuccessDialog(
            title: 'Твои старания заметили!',
            message: 'Семья подтвердила награду. Монеты начислены!',
            coins: 20,
          ),
        );
        break;
    }
  }

  Future<String?> choose(String title, Map<String, String> options) =>
      showModalBottomSheet<String>(
        context: navigation.currentState!.overlay!.context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                for (final entry in options.entries)
                  ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(context, entry.key),
                  ),
              ],
            ),
          ),
        ),
      );
  Future<void> chooseDesign() async {
    final id = await choose('Пять полных оформлений', {
      for (final d in GameDesign.all) d.id: d.name,
    });
    if (id != null && mounted) {
      gameDesign.value = GameDesign.byId(id);
      setState(() => toolbarVisible = false);
    }
  }

  Future<void> chooseRole() async {
    final role = await choose('Кто пользуется приложением', {
      'child': 'Ребёнок',
      'parent': 'Родитель',
      'relative': 'Бабушка / дедушка',
    });
    if (role != null && mounted) {
      navigation.currentState!.popUntil((r) => r.isFirst);
      repo.switchRole(role);
    }
  }

  Future<void> chooseAction() async {
    final action = await choose('Экраны и состояния', {
      'reset': 'Начать заново',
      'school': 'Уроки и оценки',
      'event': 'Создание события',
      'assistant': 'Настройки помощника',
      'call': 'Экран звонка',
      'success': 'Награда и анимация',
      'login': 'Вход и приглашение',
      'empty': 'Пустые разделы',
      'offline': 'Без интернета / вернуть связь',
      'negative': 'Отрицательный баланс',
      'large': 'Крупный / обычный текст',
      'motion': 'Включить / выключить анимацию',
    });
    if (action != null && mounted) select(action);
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: WidgetOrderTraversalPolicy(),
    child: family.MyKidsApp(
      repository: repo,
      navigationKey: navigation,
      pageSelection: pages,
      createBackground: ReviewBackground.new,
      createUpdates: ReviewUpdates.new,
      presentation: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: CallPresentation(
          builder: (_, _) => const ReviewCallPage(),
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: Material(
              color: const Color(0xffe8edf3),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(key: surface, child: app),
                  ),
                  if (toolbarVisible)
                    Positioned(
                      left: 8,
                      right: 8,
                      top: 0,
                      child: Material(
                        color: const Color(0xffe8edf3),
                        elevation: 6,
                        borderRadius: BorderRadius.circular(16),
                        child: SafeArea(
                          bottom: false,
                          child: SizedBox(
                            height: 54,
                            child: ValueListenableBuilder<GameDesign?>(
                              valueListenable: gameDesign,
                              builder: (context, design, _) => Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: chooseDesign,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              design?.name ??
                                                  'Выбор оформления',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.expand_more,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Semantics(
                                    label: 'Участник семьи',
                                    button: true,
                                    child: IconButton(
                                      onPressed: chooseRole,
                                      icon: const Icon(Icons.person_outline),
                                    ),
                                  ),
                                  Semantics(
                                    label: 'Экраны и состояния',
                                    button: true,
                                    child: IconButton(
                                      onPressed: chooseAction,
                                      icon: const Icon(Icons.grid_view_rounded),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!toolbarVisible && !externalControls)
                    Positioned(
                      right: 10,
                      bottom: MediaQuery.viewPaddingOf(context).bottom + 90,
                      child: Semantics(
                        label: 'Выбор варианта',
                        button: true,
                        child: Material(
                          color: const Color(0xffe8edf3),
                          elevation: 5,
                          borderRadius: BorderRadius.circular(24),
                          child: IconButton(
                            onPressed: () =>
                                setState(() => toolbarVisible = true),
                            icon: const Icon(Icons.palette_outlined),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Uses the actual production call layout with a synthetic media source.
/// No camera, microphone, notification, or call server is opened in review.
class ReviewCallPage extends StatefulWidget {
  const ReviewCallPage({super.key});
  @override
  State<ReviewCallPage> createState() => _ReviewCallPageState();
}

class _ReviewCallPageState extends State<ReviewCallPage> {
  bool mic = true, camera = false, speaker = true, front = true;
  final invited = <String>[];
  @override
  Widget build(BuildContext context) => FamilyCallView(
    title: 'Мама',
    status: 'Просмотр оформления звонка',
    people: [
      const CallPerson(name: 'Мама'),
      CallPerson(
        name: camera ? 'Саша · камера ${front ? 'спереди' : 'сзади'}' : 'Саша',
        local: true,
      ),
      for (final name in invited) CallPerson(name: name),
    ],
    onClose: () => Navigator.pop(context),
    controls: [
      CallControl(
        label: 'Микрофон',
        icon: mic ? Icons.mic_rounded : Icons.mic_off_rounded,
        selected: !mic,
        onPressed: () => setState(() => mic = !mic),
      ),
      CallControl(
        label: 'Камера',
        icon: camera ? Icons.videocam_rounded : Icons.videocam_off_rounded,
        selected: camera,
        onPressed: () => setState(() => camera = !camera),
      ),
      CallControl(
        label: 'Динамик',
        icon: speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
        selected: speaker,
        onPressed: () => setState(() => speaker = !speaker),
      ),
      CallControl(
        label: 'Сменить камеру',
        icon: Icons.cameraswitch_rounded,
        onPressed: camera ? () => setState(() => front = !front) : null,
      ),
      CallControl(
        label: 'Bluetooth',
        icon: Icons.bluetooth_rounded,
        onPressed: () => setState(() => speaker = false),
      ),
      CallControl(
        label: 'Пригласить',
        icon: Icons.person_add_alt_1_rounded,
        onPressed: invited.length >= 2
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Кого пригласить?'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final name in [
                        'Папа',
                        'Бабушка',
                      ].where((name) => !invited.contains(name)))
                        ListTile(
                          title: Text(name),
                          onTap: () {
                            setState(() => invited.add(name));
                            Navigator.pop(context);
                          },
                        ),
                    ],
                  ),
                ),
              ),
      ),
    ],
  );
}
