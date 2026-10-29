import 'package:flutter/material.dart';

enum RobotPart {
  wheels('Колёса', Icons.tire_repair_rounded),
  fins('Ласты', Icons.water_rounded),
  skates('Коньки', Icons.sports_hockey_rounded),
  wateringCan('Лейка', Icons.water_drop_rounded),
  gripper('Захват', Icons.precision_manufacturing_rounded),
  brush('Кисть', Icons.brush_rounded),
  leaf('Листок', Icons.eco_rounded),
  parcel('Посылка', Icons.inventory_2_rounded),
  palette('Палитра', Icons.palette_rounded);

  final String label;
  final IconData icon;
  const RobotPart(this.label, this.icon);
}

class RobotWorkshopStep {
  final String question, hint;
  final RobotPart answer;
  final List<RobotPart> choices;
  const RobotWorkshopStep(this.question, this.hint, this.answer, this.choices);
}

class RobotWorkshopChallenge {
  final String id, name, story, ending;
  final List<RobotWorkshopStep> steps;
  const RobotWorkshopChallenge(
    this.id,
    this.name,
    this.story,
    this.ending,
    this.steps,
  );
}

const robotWorkshopChallenges = [
  RobotWorkshopChallenge(
    'gardener',
    'Садовник Капля',
    'Соберём игрушечного помощника для сада на станции. Выбери три детали, которые пригодятся Капле.',
    'Капля готова! Она катится к растениям и бережно поливает ростки.',
    [
      RobotWorkshopStep(
        'На чём ехать по ровной дорожке?',
        'На дорожке нет воды и льда. Подойдут круглые детали.',
        RobotPart.wheels,
        [RobotPart.fins, RobotPart.wheels, RobotPart.skates],
      ),
      RobotWorkshopStep(
        'Чем аккуратно полить росток?',
        'Нужна деталь, из которой льётся вода.',
        RobotPart.wateringCan,
        [RobotPart.gripper, RobotPart.brush, RobotPart.wateringCan],
      ),
      RobotWorkshopStep(
        'Какой значок подойдёт садовнику?',
        'Капля заботится о зелёных растениях.',
        RobotPart.leaf,
        [RobotPart.leaf, RobotPart.parcel, RobotPart.palette],
      ),
    ],
  ),
  RobotWorkshopChallenge(
    'courier',
    'Курьер Рома',
    'На космической верфи ждут посылку. Соберём Роме колёса, полезную руку и подходящий значок.',
    'Рома собран! Посылка держится в захвате и отправляется к друзьям.',
    [
      RobotWorkshopStep(
        'На чём везти посылку по дорожке?',
        'Дорожка ровная и сухая: можно катиться.',
        RobotPart.wheels,
        [RobotPart.wheels, RobotPart.skates, RobotPart.fins],
      ),
      RobotWorkshopStep(
        'Чем удержать коробку?',
        'Выбери руку, которая умеет хватать.',
        RobotPart.gripper,
        [RobotPart.brush, RobotPart.gripper, RobotPart.wateringCan],
      ),
      RobotWorkshopStep(
        'Какой значок выбрать курьеру?',
        'Рома доставляет коробки с подарками.',
        RobotPart.parcel,
        [RobotPart.palette, RobotPart.leaf, RobotPart.parcel],
      ),
    ],
  ),
  RobotWorkshopChallenge(
    'artist',
    'Художник Искрик',
    'Искрик хочет нарисовать выдуманную комету. Соберём робота для прогулки по мастерской и рисования.',
    'Искрик готов! На его картине появилась комета с разноцветным хвостом.',
    [
      RobotWorkshopStep(
        'Что поможет катиться по полу мастерской?',
        'По сухому полу удобно ехать на колёсах.',
        RobotPart.wheels,
        [RobotPart.skates, RobotPart.fins, RobotPart.wheels],
      ),
      RobotWorkshopStep(
        'Чем рисовать красками?',
        'Эту деталь макают в краску и проводят по бумаге.',
        RobotPart.brush,
        [RobotPart.brush, RobotPart.wateringCan, RobotPart.gripper],
      ),
      RobotWorkshopStep(
        'Где смешивать цвета?',
        'У художников есть специальная дощечка для красок.',
        RobotPart.palette,
        [RobotPart.parcel, RobotPart.palette, RobotPart.leaf],
      ),
    ],
  ),
];

/// Parts stay inside this widget; building a toy never awards coins or tasks.
class RobotWorkshopGame extends StatefulWidget {
  final RobotWorkshopChallenge challenge;
  final ValueGetter<bool> canPlay;
  const RobotWorkshopGame({
    super.key,
    required this.challenge,
    required this.canPlay,
  });

  @override
  State<RobotWorkshopGame> createState() => _RobotWorkshopGameState();
}

class _RobotWorkshopGameState extends State<RobotWorkshopGame> {
  int step = 0, generation = 0;
  bool hint = false;
  String notice = '';

  @override
  void didUpdateWidget(RobotWorkshopGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.challenge, widget.challenge)) reset();
  }

  void reset() {
    step = 0;
    generation++;
    hint = false;
    notice = '';
  }

  bool allowed(RobotWorkshopChallenge expected, int captured) =>
      mounted &&
      captured == generation &&
      identical(expected, widget.challenge) &&
      widget.canPlay();

  void choose(RobotWorkshopChallenge challenge, int captured, RobotPart part) {
    if (!allowed(challenge, captured) || step == challenge.steps.length) return;
    setState(() {
      generation++;
      if (part == challenge.steps[step].answer) {
        step++;
        hint = false;
        notice = step == challenge.steps.length
            ? challenge.ending
            : 'Деталь на месте! Выберем следующую.';
      } else {
        hint = true;
        notice = 'Эту деталь оставим для другого робота. Попробуем ещё?';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.challenge;
    final captured = generation;
    final solved = step == challenge.steps.length;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(challenge.story),
        const SizedBox(height: 12),
        Text(
          'Детали робота: $step из ${challenge.steps.length}',
          key: const ValueKey('workshop-progress'),
        ),
        const SizedBox(height: 12),
        Semantics(
          label:
              'Собрано деталей: $step из ${challenge.steps.length}. '
              '${challenge.steps.take(step).map((s) => s.answer.label).join(', ')}',
          child: ExcludeSemantics(
            child: Container(
              key: const ValueKey('workshop-robot'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.smart_toy_rounded,
                    size: 56,
                    color: colors.onPrimaryContainer,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (
                        var index = 0;
                        index < challenge.steps.length;
                        index++
                      )
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              index < step
                                  ? challenge.steps[index].answer.icon
                                  : Icons.add_circle_outline_rounded,
                              size: 32,
                              color: colors.onPrimaryContainer,
                            ),
                            Text(
                              index < step
                                  ? challenge.steps[index].answer.label
                                  : '${index + 1}',
                              style: TextStyle(
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!solved) ...[
          const SizedBox(height: 16),
          Text(
            challenge.steps[step].question,
            key: const ValueKey('workshop-question'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final part in challenge.steps[step].choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                key: ValueKey('workshop-part-${part.name}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 52),
                ),
                onPressed: () => choose(challenge, captured, part),
                icon: Icon(part.icon),
                label: Text(part.label),
              ),
            ),
          if (hint)
            Text(
              'Подсказка: ${challenge.steps[step].hint}',
              key: const ValueKey('workshop-hint'),
            ),
          if (!hint)
            TextButton.icon(
              key: const ValueKey('workshop-show-hint'),
              onPressed: () {
                if (!allowed(challenge, captured)) return;
                setState(() {
                  generation++;
                  hint = true;
                });
              },
              icon: const Icon(Icons.lightbulb_outline_rounded),
              label: const Text('Подсказка'),
            ),
        ],
        if (notice.isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(notice, key: const ValueKey('workshop-feedback')),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('workshop-restart'),
          onPressed: () {
            if (allowed(challenge, captured)) setState(reset);
          },
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Собрать ещё раз'),
        ),
      ],
    );
  }
}
