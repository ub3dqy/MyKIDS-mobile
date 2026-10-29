import 'dart:math';

import 'package:flutter/material.dart';

enum SpacePair {
  star('Звезда', Icons.star_rounded),
  rocket('Ракета', Icons.rocket_launch_rounded),
  robot('Робот', Icons.smart_toy_rounded),
  moon('Луна', Icons.nightlight_round),
  planet('Планета', Icons.public_rounded),
  satellite('Спутник', Icons.satellite_alt_rounded),
  comet('Комета', Icons.auto_awesome_rounded),
  rover('Луноход', Icons.precision_manufacturing_rounded),
  flower('Цветок', Icons.local_florist_rounded);

  final String label;
  final IconData icon;
  const SpacePair(this.label, this.icon);
}

class SpaceMemoryChallenge {
  final String id, name, story;
  final List<SpacePair> cards;
  const SpaceMemoryChallenge(this.id, this.name, this.story, this.cards);
}

const spaceMemoryChallenges = [
  SpaceMemoryChallenge(
    'first-signals',
    'Первый сигнал',
    'На пульте перепутались значки. Открывай по две карточки и находи одинаковые пары.',
    [
      SpacePair.star,
      SpacePair.rocket,
      SpacePair.robot,
      SpacePair.star,
      SpacePair.robot,
      SpacePair.rocket,
    ],
  ),
  SpaceMemoryChallenge(
    'night-orbit',
    'Ночная орбита',
    'Лучик готовит карту ночной станции. Помоги найти пары её космических значков.',
    [
      SpacePair.moon,
      SpacePair.planet,
      SpacePair.satellite,
      SpacePair.moon,
      SpacePair.satellite,
      SpacePair.planet,
    ],
  ),
  SpaceMemoryChallenge(
    'garden-signals',
    'Сад комет',
    'Комета, луноход и цветок спрятались среди карточек. Найди каждой картинке друга.',
    [
      SpacePair.comet,
      SpacePair.rover,
      SpacePair.flower,
      SpacePair.rover,
      SpacePair.comet,
      SpacePair.flower,
    ],
  ),
];

/// A local board. No timers, storage, network or rewards are involved.
class SpaceMemoryGame extends StatefulWidget {
  final SpaceMemoryChallenge challenge;
  final ValueGetter<bool> canPlay;
  const SpaceMemoryGame({
    super.key,
    required this.challenge,
    required this.canPlay,
  });

  @override
  State<SpaceMemoryGame> createState() => _SpaceMemoryGameState();
}

class _SpaceMemoryGameState extends State<SpaceMemoryGame> {
  final random = Random();
  late List<SpacePair> cards;
  final matched = <int>{};
  final open = <int>[];
  bool peek = false;
  int generation = 0;
  String notice = '';

  @override
  void initState() {
    super.initState();
    reset();
  }

  @override
  void didUpdateWidget(SpaceMemoryGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.challenge, widget.challenge)) reset();
  }

  void reset() {
    generation++;
    cards = List.of(widget.challenge.cards)..shuffle(random);
    matched.clear();
    open.clear();
    peek = false;
    notice = '';
  }

  bool allowed(SpaceMemoryChallenge expected, int captured) =>
      mounted &&
      captured == generation &&
      identical(expected, widget.challenge) &&
      widget.canPlay();

  void flip(SpaceMemoryChallenge challenge, int captured, int index) {
    if (!allowed(challenge, captured) ||
        peek ||
        open.length == 2 ||
        matched.contains(index) ||
        open.contains(index)) {
      return;
    }
    setState(() {
      generation++;
      open.add(index);
      notice = 'Теперь открой ещё одну карточку.';
      if (open.length == 2) {
        if (cards[open.first] == cards[open.last]) {
          matched.addAll(open);
          open.clear();
          notice = matched.length == cards.length
              ? 'Все пары найдены! Лучик снова видит карту звёзд.'
              : 'Пара найдена! Посмотрим, кто ещё спрятался.';
        } else {
          notice = 'Карточки разные. Запомни их места и попробуй ещё.';
        }
      }
    });
  }

  Widget card(
    SpaceMemoryChallenge challenge,
    int captured,
    int index,
    ColorScheme colors,
  ) {
    final found = matched.contains(index);
    final revealed = peek || open.contains(index) || found;
    final enabled = !peek && open.length < 2 && !found && !open.contains(index);
    final symbol = cards[index];
    void action() => flip(challenge, captured, index);
    return Semantics(
      key: ValueKey('memory-card-semantics-$index'),
      container: true,
      button: true,
      enabled: enabled,
      label:
          'Карточка ${index + 1}: ${found
              ? 'найденная пара, ${symbol.label}'
              : revealed
              ? symbol.label
              : 'закрыта'}',
      onTap: enabled ? action : null,
      child: ExcludeSemantics(
        child: OutlinedButton(
          key: ValueKey('memory-card-$index'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 104),
            padding: const EdgeInsets.all(12),
            backgroundColor: found
                ? colors.primaryContainer
                : colors.surfaceContainerLow,
            foregroundColor: colors.onSurface,
            disabledForegroundColor: colors.onSurface,
          ),
          onPressed: enabled ? action : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                found
                    ? Icons.check_circle_rounded
                    : revealed
                    ? symbol.icon
                    : Icons.question_mark_rounded,
                size: 32,
              ),
              const SizedBox(height: 6),
              Text(
                revealed ? symbol.label : 'Открыть',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final challenge = widget.challenge;
    final captured = generation;
    final colors = Theme.of(context).colorScheme;
    final solved = matched.length == challenge.cards.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(challenge.story),
        const SizedBox(height: 12),
        Text(
          'Найдено пар: ${matched.length ~/ 2} из ${challenge.cards.length ~/ 2}',
          key: const ValueKey('memory-progress'),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            key: const ValueKey('memory-board'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < challenge.cards.length; index++)
                SizedBox(
                  width: (constraints.maxWidth - 8) / 2,
                  child: card(challenge, captured, index, colors),
                ),
            ],
          ),
        ),
        if (notice.isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(notice, key: const ValueKey('memory-feedback')),
          ),
        ],
        if (open.length == 2) ...[
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('memory-next'),
            onPressed: () {
              if (!allowed(challenge, captured)) return;
              setState(() {
                generation++;
                open.clear();
                notice = '';
              });
            },
            child: const Text('Ещё попытка'),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!solved)
              TextButton.icon(
                key: const ValueKey('memory-peek'),
                onPressed: () {
                  if (!allowed(challenge, captured)) return;
                  setState(() {
                    generation++;
                    peek = !peek;
                  });
                },
                icon: const Icon(Icons.visibility_outlined),
                label: Text(peek ? 'Продолжить поиск' : 'Подсмотреть карточки'),
              ),
            OutlinedButton.icon(
              key: const ValueKey('memory-restart'),
              onPressed: () {
                if (allowed(challenge, captured)) setState(reset);
              },
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Сыграть ещё'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Можно подсматривать и отдыхать. Время и попытки не считаются.',
        ),
      ],
    );
  }
}
