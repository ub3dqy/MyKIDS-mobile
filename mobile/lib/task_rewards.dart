import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'family_action.dart';
import 'form_layout.dart';

Map<String, dynamic>? taskRewardOptions(Map<String, dynamic> task) {
  final value = task['reward_options'];
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

Map<String, dynamic> mathRewardExample() => {
  'total': 6,
  'tiers': [
    {'minimum': 6, 'coins': 50},
    {'minimum': 5, 'coins': 25},
  ],
};

String? rewardOptionsError(dynamic value) {
  if (value is! Map) return 'Добавьте варианты награды';
  final total = value['total'];
  if (total is! int || total < 1 || total > 1000) {
    return 'Всего задач: целое число от 1 до 1000';
  }
  final tiers = value['tiers'];
  if (tiers is! List || tiers.isEmpty || tiers.length > 8) {
    return 'Добавьте от 1 до 8 вариантов награды';
  }
  final thresholds = <int>{};
  final ordered = <Map<String, dynamic>>[];
  for (final tier in tiers) {
    if (tier is! Map) return 'Заполните каждый вариант награды';
    final minimum = tier['minimum'];
    final coins = tier['coins'];
    if (minimum is! int || minimum < 1 || minimum > total) {
      return 'Порог награды: целое число от 1 до $total';
    }
    if (!thresholds.add(minimum)) {
      return 'У вариантов должны быть разные пороги';
    }
    if (coins is! int || coins < 0 || coins > 1000000) {
      return 'Награда: целое число от 0 до 1000000 монет';
    }
    ordered.add({'minimum': minimum, 'coins': coins});
  }
  ordered.sort((a, b) => (b['minimum'] as int).compareTo(a['minimum'] as int));
  for (var index = 1; index < ordered.length; index++) {
    if ((ordered[index - 1]['coins'] as int) <
        (ordered[index]['coins'] as int)) {
      return 'За больший результат награда не должна быть меньше';
    }
  }
  return null;
}

List<Map<String, dynamic>> rewardTiers(Map<String, dynamic> options) =>
    (options['tiers'] as List)
        .map((tier) => Map<String, dynamic>.from(tier as Map))
        .toList()
      ..sort((a, b) => (b['minimum'] as int).compareTo(a['minimum'] as int));

int taskRewardForCount(Map<String, dynamic> options, int count) {
  for (final tier in rewardTiers(options)) {
    if (count >= (tier['minimum'] as int)) return tier['coins'] as int;
  }
  return 0;
}

String taskRewardRulesText(Map<String, dynamic> options) {
  final total = options['total'] as int;
  final tiers = rewardTiers(options);
  final lines = <String>[];
  var upper = total;
  for (final tier in tiers) {
    final minimum = tier['minimum'] as int;
    final range = upper == minimum ? '$minimum' : '$minimum–$upper';
    lines.add('$range из $total — ${tier['coins']} монет');
    upper = minimum - 1;
  }
  lines.add('Меньше ${tiers.last['minimum']} — 0 монет');
  return lines.join('\n');
}

String taskAwardedText(Map<String, dynamic> task) {
  final coins = task['awarded_reward'] ?? task['reward'] ?? 0;
  final options = taskRewardOptions(task);
  final count = task['completed_count'];
  final result = options != null && count != null
      ? 'Решено верно: $count из ${options['total']}. '
      : '';
  return result +
      (coins == 0
          ? 'Проверено, без начисления монет.'
          : 'Начислено: $coins монет.');
}

class TaskRewardEditor extends StatefulWidget {
  final Map<String, dynamic> initial;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const TaskRewardEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<TaskRewardEditor> createState() => _TaskRewardEditorState();
}

class _RewardRow {
  final int id;
  final TextEditingController minimum;
  final TextEditingController coins;
  _RewardRow(this.id, dynamic threshold, dynamic amount)
    : minimum = TextEditingController(text: threshold?.toString() ?? ''),
      coins = TextEditingController(text: amount?.toString() ?? '');
  void dispose() {
    minimum.dispose();
    coins.dispose();
  }
}

class _TaskRewardEditorState extends State<TaskRewardEditor> {
  late final TextEditingController total;
  final rows = <_RewardRow>[];
  final retiredRows = <_RewardRow>[];
  var nextId = 0;

  @override
  void initState() {
    super.initState();
    total = TextEditingController(
      text: widget.initial['total']?.toString() ?? '',
    );
    for (final tier in widget.initial['tiers'] as List) {
      rows.add(_RewardRow(nextId++, tier['minimum'], tier['coins']));
    }
  }

  void changed() => widget.onChanged({
    'total': int.tryParse(total.text),
    'tiers': [
      for (final row in rows)
        {
          'minimum': int.tryParse(row.minimum.text),
          'coins': int.tryParse(row.coins.text),
        },
    ],
  });

  @override
  void dispose() {
    total.dispose();
    for (final row in [...rows, ...retiredRows]) {
      row.dispose();
    }
    super.dispose();
  }

  Widget numberField(String label, TextEditingController controller, Key key) =>
      LabeledInput(
        label: label,
        child: TextFormField(
          key: key,
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 7,
          onChanged: (_) => changed(),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: spacedFormItems([
      numberField('Всего задач', total, const ValueKey('reward-total')),
      for (final row in rows)
        Column(
          key: ValueKey('reward-row-${row.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            numberField(
              'Решено не меньше',
              row.minimum,
              ValueKey('reward-minimum-${row.id}'),
            ),
            numberField(
              'Монет за этот результат',
              row.coins,
              ValueKey('reward-coins-${row.id}'),
            ),
            if (rows.length > 1)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    rows.remove(row);
                    retiredRows.add(row);
                  });
                  changed();
                },
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('Удалить вариант'),
              ),
          ],
        ),
      OutlinedButton.icon(
        onPressed: rows.length >= 8
            ? null
            : () {
                final used = rows
                    .map((row) => int.tryParse(row.minimum.text))
                    .toSet();
                final available = int.tryParse(total.text) ?? 1;
                var minimum = 1;
                while (used.contains(minimum) && minimum < available) {
                  minimum++;
                }
                setState(() => rows.add(_RewardRow(nextId++, minimum, 0)));
                changed();
              },
        icon: const Icon(Icons.add),
        label: const Text('Добавить вариант награды'),
      ),
      const Text(
        'Если решено меньше нижнего порога, награда — 0. Начисляется одна подходящая сумма, после проверки взрослым.',
      ),
    ]),
  );
}

Future<int?> chooseTaskResult(
  BuildContext context,
  Map<String, dynamic> task, {
  FamilyActionAccess? access,
}) async {
  final options = taskRewardOptions(task)!;
  final total = options['total'] as int;
  final controller = TextEditingController();
  int? count;
  final route = DialogRoute<int>(
    context: context,
    builder: (context) => FamilyActionDialog<int>(
      access: access,
      builder: (context, close) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valid = count != null && count! >= 0 && count! <= total;
          final coins = valid ? taskRewardForCount(options, count!) : null;
          return AlertDialog(
            title: const Text('Проверить результат'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: spacedFormItems([
                Text(task['title'] as String),
                Text(taskRewardRulesText(options)),
                LabeledInput(
                  label: 'Сколько задач решено верно из $total?',
                  child: TextField(
                    key: const ValueKey('task-completed-count'),
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 4,
                    decoration: InputDecoration(
                      errorText: count != null && !valid
                          ? 'Укажите число от 0 до $total'
                          : null,
                    ),
                    onChanged: (value) =>
                        setDialogState(() => count = int.tryParse(value)),
                  ),
                ),
                Text(
                  coins == null
                      ? 'Введите результат проверки'
                      : 'Начислить: $coins монет',
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => close(null),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: valid ? () => close(count) : null,
                child: const Text('Подтвердить результат'),
              ),
            ],
          );
        },
      ),
    ),
  );
  try {
    final result = await Navigator.of(context).push(route);
    await route.completed;
    return result;
  } finally {
    controller.dispose();
  }
}
