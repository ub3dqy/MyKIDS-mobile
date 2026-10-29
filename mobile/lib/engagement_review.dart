import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'design_preferences.dart';
import 'design_review.dart'
    show ReviewBackground, ReviewUpdates, ReviewCallPage;
import 'incoming_calls.dart' show CallPresentation;
import 'design_review_bridge.dart';
import 'design_review_control.dart' show ReviewPageSelection;
import 'design_system.dart';
import 'main.dart' as family;
import 'engagement/engagement_pages.dart';
import 'engagement/engagement_scope.dart';
import 'engagement/preview_controller.dart';

/// A separate approval entry point; never connects to a family or public API.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await PreviewEngagementController.load(
    design: Uri.base.queryParameters['design'],
  );
  final role = Uri.base.queryParameters['role'];
  if (role != null && ['child', 'parent', 'relative'].contains(role)) {
    await controller.switchRole(role);
  }
  runApp(EngagementReviewApp(controller: controller));
}

class EngagementReviewApp extends StatefulWidget {
  final PreviewEngagementController controller;
  final bool disposeController;
  const EngagementReviewApp({
    super.key,
    required this.controller,
    this.disposeController = true,
  });
  @override
  State<EngagementReviewApp> createState() => _EngagementReviewAppState();
}

class _EngagementReviewAppState extends State<EngagementReviewApp> {
  final navigation = GlobalKey<NavigatorState>();
  final surface = GlobalKey();
  final pages = ReviewPageSelection();
  final errors = <String>[];
  SemanticsHandle? semantics;
  bool reducedMotion = false;
  double textScale = 1;
  String currentScreen = 'today';
  late final preferences = DesignPreferences(
    read: () async => widget.controller.designId,
    write: widget.controller.chooseDesign,
  );

  @override
  void initState() {
    super.initState();
    semantics = SemanticsBinding.instance.ensureSemantics();
    installReviewBridge(command);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = Uri.base.queryParameters['screen'];
      if (target != null && target != 'today') {
        command({'command': 'navigate', 'screen': target})
            .catchError((Object e) {
              errors.add('Не удалось открыть начальный экран');
              return <String, dynamic>{'ok': false};
            });
      }
    });
  }

  Future<void> frame() async {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> showScreen(String name, {String? id}) async {
    const original = {
      'today': 0,
      'calendar': 1,
      'tasks': 2,
      'money': 3,
      'family': 4,
      'settings': 5,
    };
    navigation.currentState!.popUntil((r) => r.isFirst);
    pages.select(0);
    await frame();
    final context = navigation.currentState!.overlay!.context;
    if (original.containsKey(name)) {
      pages.select(original[name]!);
    } else if (name == 'hero-name') {
      navigation.currentState!.push<void>(
        MaterialPageRoute<void>(builder: (_) => const HeroPage()),
      );
      await frame();
      if (context.mounted) renameHeroDialog(context);
    } else if (name == 'room-items') {
      navigation.currentState!.push<void>(
        MaterialPageRoute<void>(builder: (_) => const RoomPage()),
      );
      await frame();
      if (context.mounted) roomItemsSheet(context, 0);
    } else if (name == 'praise') {
      navigation.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const MissionPage(missionId: 'picnic'),
        ),
      );
      await frame();
      if (context.mounted) praiseDialog(context, 'picnic');
    } else {
      if (!engagementScreenNames.containsKey(name) && name != 'task') {
        throw ArgumentError('Unknown preview screen');
      }
      navigation.currentState!.push<void>(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/play/$name'),
          builder: (_) => engagementPage(name, id: id),
        ),
      );
    }
    currentScreen = name;
    await frame();
  }

  Future<Map<String, dynamic>> command(Map<String, String> args) async {
    try {
      switch (args['command']) {
        case 'navigate':
          await showScreen(args['screen'] ?? 'today', id: args['id']);
        case 'design':
          await widget.controller.chooseDesign(args['id'] ?? 'blocks');
          gameDesign.value = GameDesign.byId(widget.controller.designId);
        case 'role':
          navigation.currentState!.popUntil((r) => r.isFirst);
          await widget.controller.switchRole(args['id'] ?? 'child');
          pages.select(0);
          currentScreen = 'today';
        case 'motion':
          setState(() => reducedMotion = args['value'] == 'off');
        case 'text':
          setState(() => textScale = args['value'] == 'large' ? 1.5 : 1);
        case 'reset':
          navigation.currentState!.popUntil((r) => r.isFirst);
          await widget.controller.resetExample();
          pages.select(0);
          currentScreen = 'today';
        case 'state':
          break;
        default:
          throw ArgumentError('Unknown review command');
      }
      await frame();
      return {
        'ok': true,
        'design': widget.controller.designId,
        'role': widget.controller.role,
        'member': widget.controller.currentMemberId,
        'screen': currentScreen,
        'confirmed_tasks': widget.controller.completedCount,
        'earned_items': widget.controller.state.earned.toList(),
        'missions': widget.controller.state.missions.length,
        'storage_error': widget.controller.storageError,
        'errors': errors,
      };
    } catch (_) {
      return {
        'ok': false,
        'message': 'Не удалось выполнить действие в макете.',
      };
    }
  }

  Future<void> nativeControls(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Просмотр рабочих макетов',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              const Text('Только пробная семья. Настоящие данные не меняются.'),
              const SizedBox(height: 14),
              for (final d in GameDesign.all)
                ListTile(
                  title: Text(d.name),
                  trailing: gameDesign.value!.id == d.id
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () async {
                    Navigator.pop(sheet);
                    await command({'command': 'design', 'id': d.id});
                  },
                ),
              const Divider(),
              for (final entry in const {
                'child': 'Ребёнок',
                'parent': 'Родитель',
                'relative': 'Бабушка',
              }.entries)
                ListTile(
                  title: Text(entry.value),
                  onTap: () async {
                    Navigator.pop(sheet);
                    await command({'command': 'role', 'id': entry.key});
                  },
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => family.MyKidsApp(
    repository: widget.controller.repository,
    now: () {
      final day = DateTime.now();
      return DateTime(day.year, day.month, day.day, 16, 41);
    },
    navigationKey: navigation,
    pageSelection: pages,
    designPreferences: preferences,
    createBackground: ReviewBackground.new,
    createUpdates: ReviewUpdates.new,
    presentation: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reducedMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: EngagementScope(
        controller: widget.controller,
        child: CallPresentation(
          builder: (_, _) => const ReviewCallPage(),
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(key: surface, child: app),
              ),
              if (!kIsWeb)
                Positioned(
                  right: 12,
                  bottom: 96,
                  child: Builder(
                    builder: (context) => FloatingActionButton.small(
                      heroTag: 'preview-controls',
                      tooltip: 'Панель макета',
                      onPressed: () => nativeControls(context),
                      child: const Icon(Icons.palette_outlined),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    semantics?.dispose();
    pages.dispose();
    if (widget.disposeController) widget.controller.dispose();
    super.dispose();
  }
}
