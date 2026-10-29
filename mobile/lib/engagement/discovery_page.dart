import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system.dart';
import 'discovery_catalog.dart';
import 'engagement_model.dart';
import 'engagement_scope.dart';
import 'robot_route_game.dart';
import 'robot_workshop_game.dart';
import 'space_memory_game.dart';
import 'ray_raid_game.dart';

/// The server's durable confirmed count is the only unlock source. Riddles
/// are replayable play, with no requests, currency or locally earned progress.
class DiscoveryPage extends StatefulWidget {
  final VoidCallback? onTasks;
  const DiscoveryPage({super.key, this.onTasks});
  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

abstract class _OwnedDiscoveryState<T extends StatefulWidget> extends State<T> {
  EngagementController? _owner;
  Object? _identity;
  bool _revoked = false, closing = false;
  EngagementController get owner => _owner!;
  int get confirmed => owner.completedCount.clamp(0, 1000000000);

  bool get active {
    if (_owner == null ||
        owner.accessIdentity != _identity ||
        owner.role != 'child' ||
        owner.currentMemberId != owner.childId ||
        owner.state.enabled['adventure'] != true) {
      _revoked = true;
    }
    return !_revoked;
  }

  bool get current =>
      mounted &&
      !closing &&
      active &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = EngagementScope.maybeOf(context);
    if (controller == null) {
      _revoked = true;
      return;
    }
    if (_owner == null) {
      _owner = controller;
      _identity = controller.accessIdentity;
      controller.addListener(changed);
    } else if (!identical(_owner, controller)) {
      _revoked = true;
    }
  }

  void changed() {
    if (!active) _revoked = true;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _owner?.removeListener(changed);
    super.dispose();
  }

  void close() {
    if (!mounted ||
        closing ||
        ModalRoute.of(context)?.isCurrent != true ||
        !Navigator.of(context).canPop()) {
      return;
    }
    closing = true;
    Navigator.pop(context);
  }

  Widget frame(String title, List<Widget> children) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      leading: BackButton(onPressed: close),
    ),
    body: SafeArea(
      top: false,
      child: !active
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Доступ изменился. Закрой экспедицию и открой её заново.',
                ),
              ),
            )
          : ModalRoute.of(context)?.isCurrent != true
          ? const Center(
              child: Text('Экспедиция скрыта, пока открыт другой экран.'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: children,
            ),
    ),
  );
}

class _DiscoveryPageState extends _OwnedDiscoveryState<DiscoveryPage> {
  final Set<int> expandedWorlds = {0};
  bool initialWorldChosen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialWorldChosen && active) {
      final opened = discoveriesOpen(confirmed);
      if (opened > 0) expandedWorlds.add(spaceDiscoveries[opened - 1].world);
      initialWorldChosen = true;
    }
  }

  void training() {
    if (!current) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/play/robot-training'),
        builder: (_) => const RobotTrainingPage(),
      ),
    );
  }

  void stationGames() {
    if (!current) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/play/space-station'),
        builder: (_) => const SpaceStationPage(),
      ),
    );
  }

  void raid() {
    if (!current) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/play/ray-raid'),
        builder: (_) => const RayRaidPage(),
      ),
    );
  }

  void toggleWorld(int world) {
    if (!current) return;
    setState(() {
      if (!expandedWorlds.remove(world)) expandedWorlds.add(world);
    });
  }

  void open(SpaceDiscovery stop) {
    if (!current) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/play/discovery/${stop.id}'),
        builder: (_) => DiscoveryStopPage(
          stop: stop,
          onTasks: widget.onTasks == null ? null : tasks,
        ),
      ),
    );
  }

  void tasks() {
    if (!current || widget.onTasks == null || !Navigator.of(context).canPop()) {
      return;
    }
    closing = true;
    Navigator.pop(context);
    widget.onTasks!();
  }

  @override
  Widget build(BuildContext context) {
    final count = active ? confirmed : 0;
    final opened = discoveriesOpen(count), next = nextDiscovery(count);
    final colors = Theme.of(context).colorScheme;
    return frame('Космос с Лучиком', [
      _SpaceBanner(name: active ? owner.state.name : ''),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('ray-raid-entry'),
        onPressed: raid,
        icon: const Icon(Icons.rocket_launch_rounded),
        label: const Text('Рейд Лучика: девять миссий'),
      ),
      const SizedBox(height: 16),
      Text('Карта открытий', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
        'Открыто находок: $opened из ${spaceDiscoveries.length}',
        key: const ValueKey('discovery-progress'),
      ),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        value: opened / spaceDiscoveries.length,
        semanticsLabel:
            'Карта открытий: $opened из ${spaceDiscoveries.length} находок',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('discovery-continue'),
        onPressed: opened == 0
            ? null
            : () => open(spaceDiscoveries[opened - 1]),
        icon: const Icon(Icons.rocket_launch_rounded),
        label: const Text('В путь с Лучиком'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const ValueKey('robot-training-entry'),
        onPressed: training,
        icon: const Icon(Icons.sports_esports_rounded),
        label: const Text('Пульт Лучика'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const ValueKey('space-station-entry'),
        onPressed: stationGames,
        icon: const Icon(Icons.extension_rounded),
        label: const Text('Игры на станции'),
      ),
      const SizedBox(height: 12),
      Text(
        next == null
            ? 'Все миры открыты! Можно пересматривать находки и снова решать загадки.'
            : 'Следующее место: «${next.name}». До открытия ещё ${discoveryTaskCount(next.tasks - count)} с подтверждением семьи.',
      ),
      if (widget.onTasks != null) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: tasks,
          icon: const Icon(Icons.checklist_rounded),
          label: const Text('К моим заданиям'),
        ),
      ],
      const SizedBox(height: 12),
      for (var world = 0; world < spaceWorlds.length; world++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Semantics(
                  expanded: expandedWorlds.contains(world),
                  child: ListTile(
                    key: ValueKey('discovery-world-$world'),
                    title: Text(
                      '${world + 1}. ${spaceWorlds[world]}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      'Открыто: ${spaceDiscoveries.where((s) => s.world == world && count >= s.tasks).length} из 3',
                    ),
                    trailing: Icon(
                      expandedWorlds.contains(world)
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    onTap: () => toggleWorld(world),
                  ),
                ),
                if (expandedWorlds.contains(world))
                  for (final stop in spaceDiscoveries.where(
                    (s) => s.world == world,
                  ))
                    ListTile(
                      key: ValueKey('discovery-${stop.id}'),
                      tileColor: count >= stop.tasks
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      leading: Icon(
                        count >= stop.tasks
                            ? Icons.auto_awesome_rounded
                            : Icons.lock_outline_rounded,
                        color: count >= stop.tasks
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                      title: Text(
                        stop.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        count >= stop.tasks
                            ? 'Находка: ${stop.find}'
                            : 'До открытия ещё ${discoveryTaskCount(stop.tasks - count)}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => open(stop),
                    ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      const Text(
        'Короткие истории можно открывать в удобное время. Лучик будет ждать — карта сохраняется.',
      ),
    ]);
  }
}

class RobotTrainingPage extends StatefulWidget {
  const RobotTrainingPage({super.key});
  @override
  State<RobotTrainingPage> createState() => _RobotTrainingPageState();
}

class RayRaidPage extends StatefulWidget {
  const RayRaidPage({super.key});
  @override
  State<RayRaidPage> createState() => _RayRaidPageState();
}

class _RayRaidPageState extends _OwnedDiscoveryState<RayRaidPage> {
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: const Color(0xff081321),
      systemNavigationBarColor: const Color(0xff081321),
    ),
    child: Scaffold(
      backgroundColor: const Color(0xff081321),
      body: SafeArea(
        child: active
            ? RayRaidGame(canPlay: () => current, onExit: close)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BackButton(color: Colors.white, onPressed: close),
                  ),
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Доступ изменился. Закрой вылазку и открой её заново.',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}

class _RobotTrainingPageState extends _OwnedDiscoveryState<RobotTrainingPage> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => frame('Пульт Лучика', [
    const _SpaceBanner(name: 'Лучик', small: true),
    const SizedBox(height: 16),
    Text('Выбери полёт', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < robotRouteChallenges.length; index++)
          ChoiceChip(
            key: ValueKey('robot-challenge-$index'),
            selected: selected == index,
            label: Text(robotRouteChallenges[index].name),
            onSelected: (value) {
              if (current && value) setState(() => selected = index);
            },
          ),
      ],
    ),
    const SizedBox(height: 16),
    RobotRouteGame(
      key: ValueKey('robot-game-${robotRouteChallenges[selected].id}'),
      challenge: robotRouteChallenges[selected],
      canPlay: () => current,
    ),
    const SizedBox(height: 16),
    const Text(
      'Можно играть в своём темпе и начинать заново. Лучик будет ждать.',
    ),
    const SizedBox(height: 16),
    FilledButton(onPressed: close, child: const Text('Назад к карте')),
  ]);
}

enum SpaceStationGame { pairs, workshop }

class SpaceStationPage extends StatefulWidget {
  const SpaceStationPage({super.key});
  @override
  State<SpaceStationPage> createState() => _SpaceStationPageState();
}

class _SpaceStationPageState extends _OwnedDiscoveryState<SpaceStationPage> {
  SpaceStationGame selectedGame = SpaceStationGame.pairs;
  int level = 0;

  void select(SpaceStationGame game, int index) {
    if (!current) return;
    setState(() {
      selectedGame = game;
      level = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = selectedGame;
    final index = level;
    final names = game == SpaceStationGame.pairs
        ? spaceMemoryChallenges.map((c) => c.name).toList()
        : robotWorkshopChallenges.map((c) => c.name).toList();
    bool canPlay() => current && selectedGame == game && level == index;
    return frame('Игровая станция', [
      const _SpaceBanner(name: 'Лучик', small: true),
      const SizedBox(height: 12),
      const Text('Выбирай игру. Все игры доступны сразу и работают без сети.'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in const [
            (SpaceStationGame.pairs, 'Звёздные пары'),
            (SpaceStationGame.workshop, 'Мастерская роботов'),
          ])
            ChoiceChip(
              key: ValueKey('station-game-${item.$1.name}'),
              selected: game == item.$1,
              label: Text(item.$2),
              onSelected: (value) {
                if (value && canPlay()) select(item.$1, 0);
              },
            ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < names.length; i++)
            ChoiceChip(
              key: ValueKey('station-level-$i'),
              selected: index == i,
              label: Text(names[i]),
              onSelected: (value) {
                if (value && canPlay()) select(game, i);
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (game == SpaceStationGame.pairs)
        SpaceMemoryGame(
          key: ValueKey('station-pairs-$index'),
          challenge: spaceMemoryChallenges[index],
          canPlay: canPlay,
        )
      else
        RobotWorkshopGame(
          key: ValueKey('station-workshop-$index'),
          challenge: robotWorkshopChallenges[index],
          canPlay: canPlay,
        ),
      const SizedBox(height: 16),
      FilledButton(onPressed: close, child: const Text('Назад к карте')),
    ]);
  }
}

class DiscoveryStopPage extends StatefulWidget {
  final SpaceDiscovery stop;
  final VoidCallback? onTasks;
  const DiscoveryStopPage({super.key, required this.stop, this.onTasks});
  @override
  State<DiscoveryStopPage> createState() => _DiscoveryStopPageState();
}

class _DiscoveryStopPageState extends _OwnedDiscoveryState<DiscoveryStopPage> {
  bool hint = false, solved = false;
  int? selected;

  void choose(int index) {
    if (!current || confirmed < widget.stop.tasks || solved) return;
    setState(() {
      selected = index;
      solved = index == widget.stop.answer;
      if (!solved) hint = true;
    });
  }

  void showHint() {
    if (!current || confirmed < widget.stop.tasks) return;
    setState(() => hint = true);
  }

  Future<void> tasks() async {
    final action = widget.onTasks;
    if (!current || action == null || !Navigator.of(context).canPop()) return;
    final completed = ModalRoute.of(context)!.completed;
    closing = true;
    Navigator.pop(context);
    await completed;
    // The map's callback checks its own route and original session again.
    action();
  }

  @override
  Widget build(BuildContext context) {
    final stop = widget.stop;
    final colors = Theme.of(context).colorScheme;
    final available = active && confirmed >= stop.tasks;
    return frame(stop.name, [
      const _SpaceBanner(name: 'Лучик', small: true),
      const SizedBox(height: 18),
      if (!available) ...[
        Text(
          'Курс на новую находку',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          'До открытия ещё ${discoveryTaskCount(stop.tasks - (active ? confirmed : 0))} с подтверждением семьи.',
        ),
        const SizedBox(height: 14),
        const Text(
          'Семья проверит твои дела, и путь откроется. На карте уже есть места, куда можно заглянуть сейчас.',
        ),
        if (widget.onTasks != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: tasks,
            icon: const Icon(Icons.checklist_rounded),
            label: const Text('Выбрать дело'),
          ),
        ],
      ] else ...[
        Text(
          'Твоя находка: ${stop.find}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(stop.story),
        const SizedBox(height: 20),
        Text(
          'Загадка Лучика',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(stop.question, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (var index = 0; index < stop.choices.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              key: ValueKey('discovery-answer-$index'),
              onPressed: solved ? null : () => choose(index),
              icon: Icon(
                solved && index == stop.answer
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
              ),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(stop.choices[index]),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                disabledForegroundColor: solved && index == stop.answer
                    ? colors.onPrimaryContainer
                    : null,
                disabledBackgroundColor: solved && index == stop.answer
                    ? colors.primaryContainer
                    : null,
              ),
            ),
          ),
        if (selected != null || hint)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                solved ? 'Верно! ${stop.ending}' : 'Подсказка: ${stop.hint}',
                key: const ValueKey('discovery-feedback'),
              ),
            ),
          ),
        if (!solved && !hint)
          TextButton.icon(
            onPressed: showHint,
            icon: const Icon(Icons.lightbulb_outline_rounded),
            label: const Text('Подсказка'),
          ),
        const SizedBox(height: 12),
        const Text(
          'Это загадка для разминки — её можно решать снова. Находка уже в твоей карте.',
        ),
      ],
      const SizedBox(height: 20),
      FilledButton(onPressed: close, child: const Text('Назад к карте')),
    ]);
  }
}

class _SpaceBanner extends StatelessWidget {
  final String name;
  final bool small;
  const _SpaceBanner({required this.name, this.small = false});
  @override
  Widget build(BuildContext context) {
    final accent =
        gameDesign.value?.accent ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xff172750),
            Color.lerp(const Color(0xff172750), accent, .4)!,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.smart_toy_rounded,
            color: Color(0xffffdc77),
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              small ? 'Лучик на связи!' : '$name, выбирай курс!',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
