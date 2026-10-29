import 'package:flutter/material.dart';

typedef RobotCell = ({int row, int column});

enum RobotDirection { up, right, down, left }

enum RobotMoveKind { moved, edge, blocked, arrived }

class RobotRouteChallenge {
  final String id, name, story, hint, arrival;
  final int size;
  final RobotCell start, goal;
  final Set<RobotCell> walls;
  const RobotRouteChallenge({
    required this.id,
    required this.name,
    required this.story,
    required this.hint,
    required this.arrival,
    required this.start,
    required this.goal,
    required this.walls,
    this.size = 4,
  });

  bool contains(RobotCell cell) =>
      cell.row >= 0 &&
      cell.row < size &&
      cell.column >= 0 &&
      cell.column < size;
  bool isOpen(RobotCell cell) => contains(cell) && !walls.contains(cell);
}

const robotRouteChallenges = [
  RobotRouteChallenge(
    id: 'moon-beacon',
    name: 'Лунный маяк',
    story: 'На игровой лунной станции погас маяк. Проведи Лучика к звезде, обходя закрытые клетки, и он включит фонарик.',
    start: (row: 3, column: 0),
    goal: (row: 0, column: 3),
    walls: {(row: 1, column: 1), (row: 2, column: 1), (row: 3, column: 2)},
    hint: 'От старта можно пройти три шага вверх, а затем три вправо. Если запутался, нажми «Начать заново».',
    arrival:
        'Маяк зажёгся! Теперь игрушечный корабль видит посадочную площадку.',
  ),
  RobotRouteChallenge(
    id: 'robot-courier',
    name: 'Робот-курьер',
    story: 'Робот на другом конце станции ждёт посылку с новыми колёсиками. Доведи Лучика до звезды по свободным клеткам.',
    start: (row: 0, column: 0),
    goal: (row: 3, column: 3),
    walls: {(row: 0, column: 1), (row: 1, column: 1), (row: 2, column: 3)},
    hint: 'От старта есть путь: три шага вниз, затем три вправо. Можно вернуться к началу и попробовать его.',
    arrival: 'Посылка на месте! Друг Лучика снова катается по станции.',
  ),
  RobotRouteChallenge(
    id: 'orbital-garden',
    name: 'Орбитальный сад',
    story: 'В оранжерее ждут маленький росток. Лучик несёт его к звезде. Закрытые клетки обозначены знаком запрета.',
    start: (row: 3, column: 3),
    goal: (row: 0, column: 0),
    walls: {
      (row: 2, column: 3),
      (row: 1, column: 1),
      (row: 1, column: 0),
      (row: 3, column: 1),
    },
    hint: 'От старта: один шаг влево, три вверх и ещё два влево. Начать сначала можно в любой момент.',
    arrival: 'Росток добрался до сада! Друзья приготовили ему уютный горшочек.',
  ),
];

({RobotCell cell, RobotMoveKind kind}) moveRobot(
  RobotRouteChallenge challenge,
  RobotCell from,
  RobotDirection direction,
) {
  if (from == challenge.goal) {
    return (cell: from, kind: RobotMoveKind.arrived);
  }
  final delta = switch (direction) {
    RobotDirection.up => (row: -1, column: 0),
    RobotDirection.right => (row: 0, column: 1),
    RobotDirection.down => (row: 1, column: 0),
    RobotDirection.left => (row: 0, column: -1),
  };
  final next = (row: from.row + delta.row, column: from.column + delta.column);
  if (!challenge.contains(next)) return (cell: from, kind: RobotMoveKind.edge);
  if (challenge.walls.contains(next)) {
    return (cell: from, kind: RobotMoveKind.blocked);
  }
  return (
    cell: next,
    kind: next == challenge.goal ? RobotMoveKind.arrived : RobotMoveKind.moved,
  );
}

/// Local, replayable play. The owning page supplies its live route/session guard.
/// No repository, saved progress, network or currency action enters this widget.
class RobotRouteGame extends StatefulWidget {
  final RobotRouteChallenge challenge;
  final ValueGetter<bool> canPlay;
  const RobotRouteGame({
    super.key,
    required this.challenge,
    required this.canPlay,
  });

  @override
  State<RobotRouteGame> createState() => _RobotRouteGameState();
}

class _RobotRouteGameState extends State<RobotRouteGame> {
  late RobotCell cell;
  String notice = '';
  bool hint = false;

  @override
  void initState() {
    super.initState();
    cell = widget.challenge.start;
  }

  @override
  void didUpdateWidget(RobotRouteGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.challenge, widget.challenge)) resetState();
  }

  void resetState() {
    cell = widget.challenge.start;
    notice = '';
    hint = false;
  }

  bool allowed(RobotRouteChallenge expected) =>
      mounted && identical(expected, widget.challenge) && widget.canPlay();

  void move(RobotRouteChallenge expected, RobotDirection direction) {
    if (!allowed(expected) || cell == expected.goal) return;
    final result = moveRobot(expected, cell, direction);
    setState(() {
      cell = result.cell;
      notice = switch (result.kind) {
        RobotMoveKind.edge => 'Здесь край площадки. Попробуй другую стрелку.',
        RobotMoveKind.blocked => 'Эта клетка закрыта. Найдём путь вокруг!',
        RobotMoveKind.arrived => expected.arrival,
        RobotMoveKind.moved => 'Шаг сделан. Продолжаем путь!',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.challenge;
    final colors = Theme.of(context).colorScheme;
    final solved = cell == challenge.goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(challenge.story),
        const SizedBox(height: 12),
        Text(
          'Лучик: ряд ${cell.row + 1}, клетка ${cell.column + 1}. '
          'Звезда: ряд ${challenge.goal.row + 1}, клетка ${challenge.goal.column + 1}.',
          key: const ValueKey('robot-position'),
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              key: const ValueKey('robot-board'),
              aspectRatio: 1,
              child: Column(
                children: [
                  for (var row = 0; row < challenge.size; row++)
                    Expanded(
                      child: Row(
                        children: [
                          for (
                            var column = 0;
                            column < challenge.size;
                            column++
                          )
                            Expanded(
                              child: _RobotSquare(
                                row: row,
                                column: column,
                                robot: cell == (row: row, column: column),
                                goal:
                                    challenge.goal ==
                                    (row: row, column: column),
                                wall: challenge.walls.contains((
                                  row: row,
                                  column: column,
                                )),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Нажимай стрелки: один раз — одна клетка.'),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final control in const [
              (RobotDirection.left, Icons.arrow_back_rounded, 'Влево'),
              (RobotDirection.up, Icons.arrow_upward_rounded, 'Вверх'),
              (RobotDirection.down, Icons.arrow_downward_rounded, 'Вниз'),
              (RobotDirection.right, Icons.arrow_forward_rounded, 'Вправо'),
            ])
              IconButton.filledTonal(
                key: ValueKey('robot-${control.$1.name}'),
                tooltip: control.$3,
                constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
                onPressed: solved ? null : () => move(challenge, control.$1),
                icon: Icon(control.$2),
              ),
          ],
        ),
        if (notice.isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              notice,
              key: const ValueKey('robot-feedback'),
              style: TextStyle(
                fontWeight: solved ? FontWeight.w800 : FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
        if (hint) ...[
          const SizedBox(height: 12),
          Text(challenge.hint, key: const ValueKey('robot-hint')),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!hint && !solved)
              TextButton.icon(
                onPressed: () {
                  if (allowed(challenge)) setState(() => hint = true);
                },
                icon: const Icon(Icons.lightbulb_outline_rounded),
                label: const Text('Подсказка'),
              ),
            OutlinedButton.icon(
              key: const ValueKey('robot-restart'),
              onPressed: () {
                if (allowed(challenge)) setState(resetState);
              },
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Начать заново'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RobotSquare extends StatelessWidget {
  final int row, column;
  final bool robot, goal, wall;
  const _RobotSquare({
    required this.row,
    required this.column,
    required this.robot,
    required this.goal,
    required this.wall,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label:
          'Ряд ${row + 1}, клетка ${column + 1}: '
          '${robot
              ? (goal ? 'Лучик у звезды' : 'Лучик')
              : goal
              ? 'звезда'
              : wall
              ? 'закрыто'
              : 'свободно'}',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: robot || goal
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Center(
            child: Icon(
              robot
                  ? Icons.smart_toy_rounded
                  : goal
                  ? Icons.star_rounded
                  : wall
                  ? Icons.block_rounded
                  : Icons.circle_outlined,
              size: robot || goal
                  ? 30
                  : wall
                  ? 26
                  : 10,
              color: robot || goal
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
