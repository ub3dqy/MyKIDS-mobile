import 'package:flutter/material.dart';

import '../design_system.dart';
import 'engagement_art.dart';
import 'engagement_model.dart';
import 'engagement_pages.dart';
import 'engagement_scope.dart';
import 'discovery_page.dart';

class HeroHomeActions extends StatelessWidget {
  final VoidCallback? onTasks;
  const HeroHomeActions({super.key, this.onTasks});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.maybeOf(context);
    if (c == null ||
        c.role != 'child' ||
        (!c.state.enabled['hero']! &&
            !c.state.enabled['family']! &&
            !c.state.enabled['adventure']!)) {
      return const SizedBox.shrink();
    }
    final identity = c.accessIdentity;
    final actions = <({String screen, String label, Widget art})>[
      if (c.state.enabled['hero']!) ...[
        (
          screen: 'hero',
          label: 'Герой',
          art: EngagementAvatar(
            hero: c.state.hero,
            worn: c.state.worn,
            size: 26,
            animate: false,
          ),
        ),
        (
          screen: 'room',
          label: 'Комната',
          art: PlayItemArt(playItem('chair'), size: 25),
        ),
      ],
      if (c.state.enabled['family']!)
        (screen: 'missions', label: 'Миссии', art: const GameIcon(4, size: 25)),
      if (c.state.enabled['adventure']!)
        (
          screen: 'discoveries',
          label: 'Космос',
          art: const Icon(Icons.rocket_launch_rounded, size: 26),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, box) {
          var columns =
              actions.length == 4 ||
                  MediaQuery.textScalerOf(context).scale(16) > 21
              ? 2
              : 3;
          if (columns > actions.length) columns = actions.length;
          final width = (box.maxWidth - 10 * (columns - 1)) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final action in actions)
                SizedBox(
                  width: width,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      minimumSize: const Size(48, 52),
                    ),
                    onPressed: () {
                      if (action.screen != 'discoveries') {
                        openPlay(context, action.screen);
                        return;
                      }
                      if (!context.mounted ||
                          c.accessIdentity != identity ||
                          c.role != 'child' ||
                          c.state.enabled['adventure'] != true ||
                          ModalRoute.of(context)?.isCurrent != true) {
                        return;
                      }
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          settings: const RouteSettings(
                            name: '/play/discoveries',
                          ),
                          builder: (_) => DiscoveryPage(onTasks: onTasks),
                        ),
                      );
                    },
                    icon: action.art,
                    label: Text(action.label),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AdventureEntry extends StatelessWidget {
  const AdventureEntry({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GameDesign?>(
    valueListenable: gameDesign,
    builder: (context, design, _) {
      final c = EngagementScope.maybeOf(context);
      if (c == null || !c.state.enabled['adventure']!) {
        return const SizedBox.shrink();
      }
      final child = c.role == 'child';
      if (!child && c.role != 'parent') return const SizedBox.shrink();
      final done = c.adventureTasks.where((t) => t.completed).length;
      return Card(
        color: design?.soft,
        child: ListTile(
          leading: const GameIcon(0, size: 36),
          title: Text(
            child ? 'Моё приключение' : 'Дела ребёнка',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            child
                ? '$done из 3 шагов подтверждено семьёй'
                : 'На проверке: ${c.tasks.where((t) => t.waiting).length}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => openPlay(context, child ? 'adventure' : 'parent-review'),
        ),
      );
    },
  );
}

class FamilyMissionEntry extends StatelessWidget {
  final bool compact;
  const FamilyMissionEntry({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GameDesign?>(
    valueListenable: gameDesign,
    builder: (context, design, _) {
      final c = EngagementScope.maybeOf(context);
      if (c == null || !c.state.enabled['family']!) {
        return const SizedBox.shrink();
      }
      if (compact) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: OutlinedButton.icon(
            onPressed: () => openPlay(context, 'missions'),
            icon: const GameIcon(4, size: 28),
            label: const Text('Семейные миссии'),
          ),
        );
      }
      return Card(
        color: design?.soft,
        child: ListTile(
          leading: PlayItemArt(playItem('trophy'), size: 46),
          title: const Text(
            'Семейные миссии',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            c.state.missions.isEmpty
                ? 'Создадим общую цель'
                : c.state.missions.first.title,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => openPlay(context, 'missions'),
        ),
      );
    },
  );
}

class EngagementProfileEntries extends StatelessWidget {
  const EngagementProfileEntries({super.key});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.maybeOf(context);
    if (c == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.role == 'child') ...[
          if (c.state.enabled['hero']!) HeroHomeActions(),
          const AdventureEntry(),
          const FamilyMissionEntry(),
        ] else ...[
          if (c.role == 'parent') ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Герой и приключения'),
                subtitle: const Text('Возможности ребёнка и семейные цели'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openPlay(context, 'parent-controls'),
              ),
            ),
            const AdventureEntry(),
          ],
          const FamilyMissionEntry(),
        ],
      ],
    );
  }
}
