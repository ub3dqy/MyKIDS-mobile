import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system.dart';
import '../repository.dart' show ApiFailure;
import 'action_cancelled.dart';
import 'engagement_art.dart';
import 'engagement_model.dart';
import 'engagement_scope.dart';
import 'discovery_page.dart';

const engagementScreenNames = <String, String>{
  'hero': 'Мой герой',
  'heroes': 'Выбрать героя',
  'wardrobe': 'Одежда героя',
  'room': 'Моя комната',
  'collection': 'Моя коллекция',
  'adventure': 'Моё приключение',
  'discoveries': 'Космическая экспедиция',
  'adventure-done': 'Маршрут пройден',
  'missions': 'Семейные миссии',
  'mission': 'Наша миссия',
  'mission-done': 'Наша общая победа',
  'parent-review': 'Подтвердить дела',
  'mission-create': 'Новая семейная миссия',
  'parent-controls': 'Герой и приключения',
  'adventure-setup': 'Выбрать три задания',
};

String adventureName(String id) => switch (id) {
  'blocks' => 'Построим свою базу',
  'squad' => 'Готовимся к полёту',
  'comic' => 'Собираем команду героев',
  'workshop' => 'Открываем мастерскую',
  _ => 'Отправляемся на остров',
};

Future<void> playAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (error) {
    if (error is PlayActionCancelled) return;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiFailure
                ? error.message
                : 'Не получилось сохранить. Попробуй ещё раз.',
          ),
        ),
      );
    }
  }
}

Widget engagementPage(String name, {String? id}) => switch (name) {
  'hero' => const HeroPage(),
  'heroes' => const HeroChoicePage(),
  'wardrobe' => const WardrobePage(),
  'room' => const RoomPage(),
  'collection' => const CollectionPage(),
  'adventure' => const AdventurePage(),
  'discoveries' => const DiscoveryPage(),
  'task' => Builder(
    builder: (context) => AdventureTaskPage(
      taskId:
          id ??
          EngagementScope.of(context).tasks
              .where((t) => t.canSubmit)
              .firstOrNull
              ?.id ??
          EngagementScope.of(context).tasks.firstOrNull?.id ??
          '',
    ),
  ),
  'adventure-done' => const PlayCompletionPage(),
  'missions' => const MissionsPage(),
  'mission' => Builder(
    builder: (context) => MissionPage(
      missionId:
          id ??
          EngagementScope.of(context).state.missions.firstOrNull?.id ??
          '',
    ),
  ),
  'mission-done' => Builder(
    builder: (context) => PlayCompletionPage(
      missionId:
          id ??
          EngagementScope.of(context).state.missions.firstOrNull?.id ??
          '',
    ),
  ),
  'parent-review' => const ParentReviewPage(),
  'mission-create' => const MissionCreatePage(),
  'parent-controls' => const PlayParentControlsPage(),
  'adventure-setup' => const AdventureSetupPage(),
  _ => throw ArgumentError('Unknown engagement screen'),
};

Future<void> openPlay(BuildContext context, String name, {String? id}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/play/$name', arguments: id),
        builder: (_) => engagementPage(name, id: id),
      ),
    );

class PlayScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool parentOnly;
  final String? feature;
  const PlayScaffold({
    super.key,
    required this.title,
    required this.children,
    this.parentOnly = false,
    this.feature,
  });
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child:
            c.role == 'child' && feature != null && !c.state.enabled[feature]!
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Семья пока выключила этот раздел. Твои открытия сохранены.',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () =>
                            Navigator.popUntil(context, (r) => r.isFirst),
                        child: const Text('На главную'),
                      ),
                    ],
                  ),
                ),
              )
            : parentOnly && c.role != 'parent'
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Этот раздел открывает родитель.'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (c.storageError != null)
                    _Notice(c.storageError!, icon: Icons.cloud_off_rounded),
                  ...children,
                ],
              ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String title, subtitle;
  const _Heading(this.title, this.subtitle);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 7),
        Text(subtitle),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Notice(this.text, {this.icon = Icons.info_outline_rounded});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: gameDesign.value!.soft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 23),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );
}

Widget _link(
  BuildContext context, {
  required String title,
  required String note,
  required Widget art,
  required VoidCallback tap,
}) => Card(
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    leading: SizedBox.square(dimension: 54, child: FittedBox(child: art)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
    subtitle: Text(note),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: tap,
  ),
);

class HeroPage extends StatelessWidget {
  const HeroPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    final count = playItems.where(c.unlocked).length;
    return PlayScaffold(
      title: 'Мой герой',
      feature: 'hero',
      children: [
        _Heading(
          c.state.name,
          'Твой герой. Твои открытия. Твоя уютная комната.',
        ),
        PlayRoom(controller: c),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => openPlay(context, 'heroes'),
                icon: const Icon(Icons.face_rounded),
                label: const Text('Герой'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => openPlay(context, 'wardrobe'),
                icon: const Icon(Icons.checkroom_rounded),
                label: const Text('Одежда'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => renameHeroDialog(context),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Придумать имя'),
        ),
        const SizedBox(height: 20),
        _link(
          context,
          title: 'Моя комната',
          note: 'Расставь открытые предметы',
          art: PlayItemArt(playItem('chair')),
          tap: () => openPlay(context, 'room'),
        ),
        _link(
          context,
          title: 'Моя коллекция',
          note: 'Открыто $count из ${playItems.length}',
          art: PlayItemArt(playItem('trophy')),
          tap: () => openPlay(context, 'collection'),
        ),
        _Notice(
          'Подтверждено дел: ${c.completedCount}. Новые предметы открываются за твои старания. Монеты остаются для семейных наград.',
        ),
      ],
    );
  }
}

Future<void> renameHeroDialog(BuildContext context) async {
  final c = EngagementScope.of(context);
  final input = TextEditingController(text: c.state.name);
  final form = GlobalKey<FormState>();
  try {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Как зовут героя?'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: input,
            autofocus: true,
            maxLength: 18,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [
              FilteringTextInputFormatter.deny(
                RegExp(r'[\x00-\x1f\u202a-\u202e\u2066-\u2069]'),
              ),
            ],
            decoration: const InputDecoration(
              labelText: 'Имя героя',
              helperText: 'Можно придумать любое короткое имя',
              helperMaxLines: 2,
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Напиши имя' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              try {
                await c.renameHero(input.text);
                if (dialog.mounted) Navigator.pop(dialog);
              } catch (_) {
                if (dialog.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Имя не сохранилось. Попробуй ещё раз.'),
                    ),
                  );
                }
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  } finally {
    input.dispose();
  }
}

class HeroChoicePage extends StatelessWidget {
  const HeroChoicePage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    const names = [
      'Искатель',
      'Звёздный друг',
      'Кот-комикс',
      'Мастер',
      'Путешественник',
    ];
    return PlayScaffold(
      title: 'Выбрать героя',
      feature: 'hero',
      children: [
        const _Heading(
          'Кто отправится с тобой?',
          'Имя, одежда и открытые предметы сохранятся.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Герой оформления'),
          subtitle: const Text('Персонаж меняется вместе с выбранным миром'),
          value: c.state.hero == 'auto',
          onChanged: c.busy
              ? null
              : (value) => playAction(
                  context,
                  () => c.chooseHero(value ? 'auto' : gameDesign.value!.id),
                ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < GameDesign.all.length; i++)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: EngagementAvatar(
                hero: GameDesign.all[i].id,
                size: 76,
                animate: false,
              ),
              title: Text(
                names[i],
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(GameDesign.all[i].name),
              trailing: c.state.hero == GameDesign.all[i].id
                  ? const Icon(Icons.check_circle_rounded)
                  : const Icon(Icons.radio_button_unchecked),
              onTap: c.busy
                  ? null
                  : () => playAction(
                      context,
                      () => c.chooseHero(GameDesign.all[i].id),
                      success: 'Герой выбран',
                    ),
            ),
          ),
      ],
    );
  }
}

class WardrobePage extends StatelessWidget {
  const WardrobePage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    return PlayScaffold(
      title: 'Одежда героя',
      feature: 'hero',
      children: [
        Center(
          child: EngagementAvatar(
            hero: c.state.hero,
            worn: c.state.worn,
            size: 220,
          ),
        ),
        const _Heading(
          'Выбери свой образ',
          'Нажми на открытый предмет, чтобы надеть или снять его.',
        ),
        for (final item in playItems.where((i) => i.wearable))
          _ItemTile(
            item: item,
            selected: c.state.worn.contains(item.id),
            onTap: () => playAction(context, () => c.wear(item.id)),
          ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  final PlayItem item;
  final bool selected;
  final VoidCallback? onTap;
  const _ItemTile({required this.item, this.selected = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context),
        open = EngagementScope.of(context).unlocked(item);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: SizedBox.square(
          dimension: 70,
          child: PlayItemArt(item, size: 70),
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          open
              ? selected
                    ? 'Уже выбрано'
                    : item.description
              : c.unlockText(item),
        ),
        trailing: Icon(
          !open
              ? Icons.lock_outline_rounded
              : selected
              ? Icons.check_circle_rounded
              : Icons.add_circle_outline_rounded,
        ),
        onTap: !open || c.busy
            ? () => showItemInfo(context, item)
            : onTap ?? () => showItemInfo(context, item),
      ),
    );
  }
}

Future<void> showItemInfo(BuildContext context, PlayItem item) {
  final c = EngagementScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(item.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayItemArt(item, size: 150),
          const SizedBox(height: 14),
          Text(c.unlocked(item) ? item.description : c.unlockText(item)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
}

class RoomPage extends StatelessWidget {
  const RoomPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    return PlayScaffold(
      title: 'Моя комната',
      feature: 'hero',
      children: [
        const _Heading(
          'Здесь всё по-твоему',
          'Выбери место в комнате, а потом предмет.',
        ),
        PlayRoom(
          controller: c,
          onSlot: (slot) => roomItemsSheet(context, slot),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 3; i++)
          _link(
            context,
            title: 'Место ${i + 1}',
            note: c.state.room[i] == null
                ? 'Пока свободно'
                : playItem(c.state.room[i]!).name,
            art: c.state.room[i] == null
                ? const Icon(Icons.add_rounded, size: 36)
                : PlayItemArt(playItem(c.state.room[i]!)),
            tap: () => roomItemsSheet(context, i),
          ),
        const _Notice(
          'Предметы можно переставлять. Все твои открытия сохраняются в любом оформлении.',
        ),
      ],
    );
  }
}

Future<void> roomItemsSheet(BuildContext context, int slot) {
  // Read before the modal removes the top system inset from its MediaQuery.
  final contentHeight =
      MediaQuery.sizeOf(context).height -
      MediaQuery.viewPaddingOf(context).vertical;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: contentHeight * .76,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            _Heading(
              'Предмет для места ${slot + 1}',
              'Выбранная вещь переместится сюда.',
            ),
            OutlinedButton(
              onPressed: () async {
                try {
                  await EngagementScope.of(sheet).place(null, slot);
                  if (sheet.mounted) Navigator.pop(sheet);
                } catch (_) {
                  if (sheet.mounted) {
                    await playAction(
                      sheet,
                      () async => throw StateError('save'),
                    );
                  }
                }
              },
              child: const Text('Оставить место пустым'),
            ),
            const SizedBox(height: 12),
            for (final item in playItems.where((i) => !i.wearable))
              _ItemTile(
                item: item,
                selected: EngagementScope.of(sheet).state.room[slot] == item.id,
                onTap: () async {
                  try {
                    await EngagementScope.of(sheet).place(item.id, slot);
                    if (sheet.mounted) Navigator.pop(sheet);
                  } catch (_) {
                    if (sheet.mounted) {
                      await playAction(
                        sheet,
                        () async => throw StateError('save'),
                      );
                    }
                  }
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    return PlayScaffold(
      title: 'Моя коллекция',
      feature: 'hero',
      children: [
        _Heading(
          'Маленькие дела — большие открытия',
          'Подтверждено дел: ${c.completedCount}. Открыто предметов: ${playItems.where(c.unlocked).length} из ${playItems.length}.',
        ),
        for (final item in playItems) _ItemTile(item: item),
        const _Notice(
          'Предметы не покупаются за семейные монеты. С ними можно играть в своей комнате и менять образ героя.',
        ),
      ],
    );
  }
}

class AdventurePage extends StatelessWidget {
  const AdventurePage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context),
        tasks = EngagementScope.of(context).adventureTasks;
    final done = tasks.where((t) => t.completed).length;
    return PlayScaffold(
      title: 'Моё приключение',
      feature: 'adventure',
      children: [
        _Heading(
          adventureName(gameDesign.value!.id),
          'Три настоящих дела. Три шага к новым открытиям.',
        ),
        if (tasks.isEmpty)
          const _Notice(
            'Семья скоро выберет три дела для твоего первого приключения.',
          )
        else
          AdventureMap(
            tasks: tasks,
            onTask: (id) => openPlay(context, 'task', id: id),
          ),
        const SizedBox(height: 16),
        Text(
          'Семья подтвердила $done из ${tasks.length}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: tasks.isEmpty ? 0 : done / tasks.length),
        const SizedBox(height: 18),
        for (var i = 0; i < tasks.length; i++)
          _TaskTile(task: tasks[i], index: i + 1),
        if (done == 3)
          FilledButton.icon(
            onPressed: c.busy
                ? null
                : () async {
                    await playAction(context, c.claimAdventure);
                    if (context.mounted && c.state.adventureClaimed) {
                      openPlay(context, 'adventure-done');
                    }
                  },
            icon: const Icon(Icons.celebration_rounded),
            label: Text(
              c.state.adventureClaimed
                  ? 'Посмотреть свою победу'
                  : 'Отметить свою победу',
            ),
          ),
        if (done != 3)
          const _Notice(
            'Сначала сделай дело, затем отправь результат семье. После подтверждения откроются предметы. Можно двигаться в своём порядке.',
          ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  final PlayTask task;
  final int? index;
  const _TaskTile({required this.task, this.index});
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      leading: CircleAvatar(
        backgroundColor: gameDesign.value!.soft,
        child: task.completed
            ? const Icon(Icons.check_rounded)
            : task.waiting
            ? const Icon(Icons.hourglass_top_rounded)
            : Text('${index ?? '•'}'),
      ),
      title: Text(
        task.title,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        task.completed
            ? 'Семья подтвердила'
            : task.waiting
            ? 'Ждём подтверждения семьи'
            : task.status == 'returned'
            ? 'Нужно немного поправить'
            : 'Можно начать',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => openPlay(context, 'task', id: task.id),
    ),
  );
}

class AdventureMap extends StatelessWidget {
  final List<PlayTask> tasks;
  final ValueChanged<String> onTask;
  const AdventureMap({super.key, required this.tasks, required this.onTask});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(gameDesign.value!.radius),
    child: SizedBox(
      height:
          350 +
          (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 100) * 10,
      child: LayoutBuilder(
        builder: (context, size) {
          const points = [Offset(.22, .16), Offset(.72, .48), Offset(.25, .81)];
          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: gameDesign.value!.soft)),
              Positioned.fill(
                child: Opacity(
                  opacity: .10,
                  child: Image.asset(
                    gameDesign.value!.scene,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _AdventurePath(gameDesign.value!.accent),
                ),
              ),
              for (var i = 0; i < tasks.length && i < 3; i++)
                Positioned(
                  left: size.maxWidth * points[i].dx - 42,
                  top: size.maxHeight * points[i].dy - 38,
                  width: 84,
                  height:
                      100 +
                      (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
                            0,
                            100,
                          ) *
                          2,
                  child: Semantics(
                    label: 'Шаг ${i + 1}: ${tasks[i].title}',
                    button: true,
                    child: InkWell(
                      onTap: () => onTask(tasks[i].id),
                      borderRadius: BorderRadius.circular(22),
                      child: Column(
                        children: [
                          Container(
                            width: 75,
                            height: 72,
                            decoration: BoxDecoration(
                              color: tasks[i].completed
                                  ? gameDesign.value!.reward
                                  : gameDesign.value!.surface,
                              borderRadius: BorderRadius.circular(23),
                              border: Border.all(
                                color: gameDesign.value!.accent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: gameDesign.value!.outline,
                                  offset: const Offset(0, 4),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (tasks[i].title.toLowerCase().contains(
                                  'цвет',
                                ))
                                  PlayItemArt(playItem('plant'), size: 53)
                                else if (tasks[i].title.toLowerCase().contains(
                                  'чит',
                                ))
                                  const GameIcon(1, size: 50)
                                else if (tasks[i].title.toLowerCase().contains(
                                  'рюкзак',
                                ))
                                  const GameIcon(9, size: 50)
                                else
                                  const Icon(Icons.task_alt_rounded, size: 46),
                                if (tasks[i].completed || tasks[i].waiting)
                                  Positioned(
                                    right: 1,
                                    bottom: 1,
                                    child: CircleAvatar(
                                      radius: 12,
                                      backgroundColor: gameDesign.value!.accent,
                                      child: Icon(
                                        tasks[i].completed
                                            ? Icons.check_rounded
                                            : Icons.hourglass_top_rounded,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Шаг ${i + 1}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _AdventurePath extends CustomPainter {
  final Color color;
  _AdventurePath(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .22, size.height * .16)
      ..cubicTo(
        size.width * .20,
        size.height * .42,
        size.width * .75,
        size.height * .24,
        size.width * .72,
        size.height * .48,
      )
      ..cubicTo(
        size.width * .70,
        size.height * .72,
        size.width * .28,
        size.height * .60,
        size.width * .25,
        size.height * .81,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .24)
        ..strokeWidth = 13
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final metric in path.computeMetrics()) {
      for (double at = 0; at < metric.length; at += 22) {
        final tangent = metric.getTangentForOffset(at)!;
        canvas.drawCircle(tangent.position, 3.2, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_AdventurePath old) => old.color != color;
}

class AdventureTaskPage extends StatefulWidget {
  final String taskId;
  const AdventureTaskPage({super.key, required this.taskId});
  @override
  State<AdventureTaskPage> createState() => _AdventureTaskPageState();
}

class _AdventureTaskPageState extends State<AdventureTaskPage> {
  final note = TextEditingController();
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    final task = c.tasks.where((t) => t.id == widget.taskId).firstOrNull;
    if (task == null) {
      return const PlayScaffold(
        title: 'Задание',
        children: [_Notice('Это задание больше недоступно.')],
      );
    }
    return PlayScaffold(
      title: 'Мой шаг',
      children: [
        _Heading(task.title, task.note),
        Center(
          child: EngagementAvatar(
            hero: c.state.hero,
            worn: c.state.worn,
            size: 150,
            celebrate: task.completed,
          ),
        ),
        _Notice(
          task.completed
              ? 'Отличная работа! Семья подтвердила твой результат.'
              : task.waiting
              ? 'Результат у семьи. Пока можно заняться другим делом.'
              : task.status == 'returned'
              ? 'Семья просит немного поправить результат. Подсказка есть ниже.'
              : 'Выполни дело и расскажи семье, что получилось.',
        ),
        if (task.status == 'returned' && task.reviewNote.isNotEmpty)
          _Notice(
            'Подсказка семьи: ${task.reviewNote}',
            icon: Icons.favorite_outline_rounded,
          ),
        if (task.submissionNote.isNotEmpty)
          _Notice(
            'Рассказ ребёнка: ${task.submissionNote}',
            icon: Icons.chat_bubble_outline_rounded,
          ),
        if (task.reward > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              'После подтверждения: ${task.reward} монет',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        if (c.role == 'child' && task.canSubmit) ...[
          TextField(
            controller: note,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Как ты справился?',
              helperText:
                  'Можно оставить короткий рассказ или отправить без него',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: c.busy
                ? null
                : () => playAction(
                    context,
                    () => c.submit(task.id, note.text),
                    success: 'Результат отправлен семье',
                  ),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Готово — отправить семье'),
          ),
        ],
        if (c.role == 'parent' && task.waiting) ...[
          FilledButton(
            onPressed: c.busy
                ? null
                : () => playAction(
                    context,
                    () => c.review(task.id, approve: true),
                    success: 'Дело подтверждено',
                  ),
            child: const Text('Подтвердить результат'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => returnTaskDialog(context, task.id),
            child: const Text('Попросить поправить'),
          ),
        ],
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => openPlay(context, 'adventure'),
          child: const Text('Моё приключение'),
        ),
      ],
    );
  }
}

Future<void> returnTaskDialog(BuildContext context, String taskId) async {
  final text = TextEditingController();
  final form = GlobalKey<FormState>();
  try {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Что нужно поправить?'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: text,
            maxLength: 240,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Добрая и понятная подсказка',
            ),
            validator: (s) =>
                s == null || s.trim().isEmpty ? 'Добавьте подсказку' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              try {
                await EngagementScope.of(context)
                    .review(taskId, approve: false, note: text.text);
                if (dialog.mounted) Navigator.pop(dialog);
              } catch (_) {
                if (dialog.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Не удалось сохранить подсказку.'),
                    ),
                  );
                }
              }
            },
            child: const Text('Отправить подсказку'),
          ),
        ],
      ),
    );
  } finally {
    text.dispose();
  }
}

class MissionsPage extends StatelessWidget {
  const MissionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    return PlayScaffold(
      title: 'Семейные миссии',
      feature: 'family',
      children: [
        const _Heading(
          'Вместе получается больше',
          'У каждого своё маленькое дело. Победа — общая.',
        ),
        for (final mission in c.state.missions)
          Card(
            child: InkWell(
              onTap: () => openPlay(context, 'mission', id: mission.id),
              borderRadius: BorderRadius.circular(gameDesign.value!.radius),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PlayItemArt(
                          playItem(
                            mission.title.toLowerCase().contains('пикник')
                                ? 'plant'
                                : 'trophy',
                          ),
                          size: 66,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            mission.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(mission.description),
                    const SizedBox(height: 14),
                    _FamilyFaces(mission: mission),
                    const SizedBox(height: 10),
                    Text(
                      c.missionDone(mission)
                          ? 'Мы справились!'
                          : 'Готово ${mission.steps.where(c.stepDone).length} из 3',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (c.role == 'parent')
          FilledButton.icon(
            onPressed: () => openPlay(context, 'mission-create'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Создать семейную миссию'),
          ),
      ],
    );
  }
}

class _FamilyFaces extends StatelessWidget {
  final FamilyMission mission;
  const _FamilyFaces({required this.mission});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    return Wrap(
      spacing: 18,
      runSpacing: 10,
      children: [
        for (final step in mission.steps)
          Column(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: c.stepDone(step)
                    ? gameDesign.value!.reward
                    : gameDesign.value!.soft,
                child: Icon(
                  c.stepDone(step)
                      ? Icons.check_rounded
                      : c.memberRole(step.owner) == 'child'
                      ? Icons.face_rounded
                      : Icons.person_rounded,
                  color: gameDesign.value!.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                c.memberName(step.owner),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
      ],
    );
  }
}

class MissionPage extends StatelessWidget {
  final String missionId;
  const MissionPage({super.key, required this.missionId});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    final mission = c.state.missions
        .where((m) => m.id == missionId)
        .firstOrNull;
    if (mission == null) {
      return const PlayScaffold(
        title: 'Наша миссия',
        children: [_Notice('Миссия больше недоступна.')],
      );
    }
    final joined = c.state.joined.contains(mission.id);
    return PlayScaffold(
      title: 'Наша миссия',
      feature: 'family',
      children: [
        _Heading(mission.title, mission.description),
        GameScene(
          title: 'Мы — команда!',
          description: 'Общая цель: ${mission.reward}',
          compact: true,
        ),
        const SizedBox(height: 14),
        _FamilyFaces(mission: mission),
        const SizedBox(height: 20),
        if (c.role == 'child' && !joined)
          FilledButton.icon(
            onPressed: c.busy
                ? null
                : () => playAction(
                    context,
                    () => c.join(mission.id),
                    success: 'Ты в команде!',
                  ),
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Я с вами!'),
          ),
        for (final step in mission.steps)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        c.stepDone(step)
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        c.memberName(step.owner),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(step.title),
                  if (!c.stepDone(step) &&
                      step.owner == c.currentMemberId &&
                      step.taskId == null) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: c.busy
                          ? null
                          : () => playAction(
                              context,
                              () => c.markOwnStep(mission.id, step.id),
                              success: 'Твой шаг готов',
                            ),
                      child: const Text('Моё дело готово'),
                    ),
                  ],
                  if (step.taskId != null && (c.role != 'child' || joined)) ...[
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () =>
                          openPlay(context, 'task', id: step.taskId),
                      child: Text(
                        c.role == 'child'
                            ? 'Открыть мой шаг'
                            : 'Посмотреть результат ребёнка',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (c.missionDone(mission)) ...[
          const _Notice(
            'Все дела подтверждены. Можно отмечать общую победу!',
            icon: Icons.celebration_rounded,
          ),
          if (c.role == 'child' && joined)
            FilledButton(
              onPressed: c.busy
                  ? null
                  : () async {
                      await playAction(
                        context,
                        () => c.claimMission(mission.id),
                      );
                      if (context.mounted &&
                          c.state.claimedMissions.contains(mission.id)) {
                        openPlay(context, 'mission-done', id: mission.id);
                      }
                    },
              child: const Text('Наша общая победа!'),
            ),
        ] else
          const _Notice(
            'Каждый отмечает своё дело. Результат ребёнка подтверждает родитель.',
          ),
        const SizedBox(height: 12),
        if (c.role != 'child')
          OutlinedButton.icon(
            onPressed: () => praiseDialog(context, mission.id),
            icon: const Icon(Icons.favorite_rounded),
            label: const Text('Поддержать ребёнка'),
          ),
        for (final praise in c.state.praise.where(
          (p) => p['mission'] == mission.id,
        ))
          Card(
            child: ListTile(
              leading: PlayItemArt(playItem('badge'), size: 42),
              title: Text(praise['text']!),
              subtitle: Text(c.memberName(praise['sender']!)),
            ),
          ),
        if (c.role == 'child' &&
            c.state.praise.any(
              (p) =>
                  p['mission'] == mission.id &&
                  p['sender'] != c.currentMemberId,
            ))
          OutlinedButton(
            onPressed: c.busy
                ? null
                : () => playAction(
                    context,
                    () => c.sendPraise(mission.id, 'Спасибо!'),
                    success: 'Спасибо отправлено семье',
                  ),
            child: const Text('Сказать спасибо'),
          ),
      ],
    );
  }
}

Future<void> praiseDialog(BuildContext context, String missionId) =>
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Тёплые слова для ребёнка'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final text in praiseMessages.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton(
                  onPressed: () async {
                    await playAction(
                      context,
                      () =>
                          EngagementScope.of(context)
                              .sendPraise(missionId, text),
                    );
                    if (dialog.mounted) Navigator.pop(dialog);
                  },
                  child: Text(text),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );

class PlayCompletionPage extends StatelessWidget {
  final String? missionId;
  const PlayCompletionPage({super.key, this.missionId});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    final mission = c.state.missions
        .where((m) => m.id == missionId)
        .firstOrNull;
    final ready = missionId == null
        ? c.state.adventureClaimed
        : mission != null && c.state.claimedMissions.contains(missionId);
    return PlayScaffold(
      title: missionId == null ? 'Маршрут пройден' : 'Наша общая победа',
      children: [
        if (!ready) ...[
          const _Heading(
            'Всё впереди!',
            'Сначала завершим дела и получим подтверждение семьи.',
          ),
          FilledButton(
            onPressed: () =>
                openPlay(context, missionId == null ? 'adventure' : 'missions'),
            child: const Text('Посмотреть мои шаги'),
          ),
        ] else ...[
          Center(
            child: EngagementAvatar(
              hero: c.state.hero,
              worn: c.state.worn,
              size: 230,
              celebrate: true,
            ),
          ),
          _Heading(
            missionId == null
                ? 'Ты прошёл весь маршрут!'
                : 'Мы справились вместе!',
            missionId == null
                ? 'Три подтверждённых дела. Теперь у тебя есть плащ героя и новые вещи для комнаты.'
                : 'В коллекции появился кубок «Наша общая победа».',
          ),
          Center(
            child: PlayItemArt(
              playItem(missionId == null ? 'cape' : 'trophy'),
              size: 130,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () =>
                openPlay(context, missionId == null ? 'wardrobe' : 'room'),
            child: Text(
              missionId == null
                  ? 'Примерить плащ'
                  : 'Поставить кубок в комнате',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            child: const Text('На главную'),
          ),
        ],
      ],
    );
  }
}

class ParentReviewPage extends StatelessWidget {
  const ParentReviewPage({super.key});
  @override
  Widget build(BuildContext context) {
    final waiting = EngagementScope.of(context).tasks
        .where((t) => t.waiting)
        .toList();
    return PlayScaffold(
      title: 'Подтвердить дела',
      parentOnly: true,
      children: [
        const _Heading(
          'Ребёнок уже постарался',
          'После подтверждения продвигается приключение и открываются новые предметы.',
        ),
        if (waiting.isEmpty)
          const _Notice(
            'Пока нечего проверять. Отправленные результаты появятся здесь.',
          ),
        for (final task in waiting) _TaskTile(task: task),
        const SizedBox(height: 16),
        const _Notice(
          'Монеты начисляются по обычным правилам задания. Повторное подтверждение не добавляет награду ещё раз.',
        ),
      ],
    );
  }
}

class PlayParentControlsPage extends StatelessWidget {
  const PlayParentControlsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    return PlayScaffold(
      title: 'Герой и приключения',
      parentOnly: true,
      children: [
        const _Heading(
          'Новые возможности ребёнка',
          'Выберите, что доступно вашей семье.',
        ),
        for (final entry in const {
          'hero': 'Мой герой и комната',
          'adventure': 'Приключения и космос',
          'family': 'Семейные миссии',
        }.entries)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.value),
            value: c.state.enabled[entry.key]!,
            onChanged: c.busy
                ? null
                : (value) =>
                      playAction(context, () => c.setEnabled(entry.key, value)),
          ),
        const _Notice(
          'Открытые вещи и пройденные шаги сохранятся, даже если временно выключить раздел.',
        ),
        FilledButton(
          onPressed: () => openPlay(context, 'parent-review'),
          child: const Text('Подтвердить дела ребёнка'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => openPlay(context, 'adventure-setup'),
          child: const Text('Выбрать три дела для приключения'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => openPlay(context, 'mission-create'),
          child: const Text('Создать семейную миссию'),
        ),
      ],
    );
  }
}

class MissionCreatePage extends StatefulWidget {
  const MissionCreatePage({super.key});
  @override
  State<MissionCreatePage> createState() => _MissionCreatePageState();
}

class _MissionCreatePageState extends State<MissionCreatePage> {
  final form = GlobalKey<FormState>();
  final fields = List.generate(6, (_) => TextEditingController());
  String? helperId;
  Set<String>? submittedIds;
  List<String>? submittedFields;
  String? submittedHelper, submittedOwner;
  bool openingMission = false;
  bool creationAccepted = false;

  void openCreatedMission(EngagementController c) {
    if (submittedIds == null ||
        openingMission ||
        !creationAccepted ||
        c.busy ||
        c.storageError != null) {
      return;
    }
    final values = submittedFields!;
    final mission = c.state.missions
        .where(
          (m) =>
              !submittedIds!.contains(m.id) &&
              m.title == values[0] &&
              m.description == values[1] &&
              m.reward == values[2] &&
              m.steps.length == 3 &&
              m.steps[0].title == values[3] &&
              m.steps[1].title == values[4] &&
              m.steps[1].owner == submittedOwner &&
              m.steps[2].title == values[5] &&
              m.steps[2].owner == submittedHelper,
        )
        .firstOrNull;
    if (mission == null) return;
    openingMission = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MissionPage(missionId: mission.id),
        ),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    openCreatedMission(EngagementScope.of(context));
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    final helpers = c.members
        .where((m) => m.role != 'child' && m.id != c.currentMemberId)
        .toList();
    if (!helpers.any((m) => m.id == helperId)) {
      helperId = helpers.firstOrNull?.id;
    }
    const labels = [
      'Название миссии',
      'Что будем делать вместе',
      'Общая награда или событие',
      'Дело ребёнка',
      'Моё дело',
      'Дело помощника',
    ];
    return PlayScaffold(
      title: 'Новая семейная миссия',
      parentOnly: true,
      children: [
        const _Heading(
          'Одна цель на всю семью',
          'Три понятных дела — по одному для каждого.',
        ),
        Form(
          key: form,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(helperId),
                initialValue: helperId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Кто ещё участвует',
                ),
                items: helpers
                    .map(
                      (m) => DropdownMenuItem(value: m.id, child: Text(m.name)),
                    )
                    .toList(),
                onChanged: (id) => setState(() => helperId = id),
                validator: (id) => id == null
                    ? 'Пригласите ещё одного взрослого в семью'
                    : null,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: fields[i],
                    maxLength: i == 0
                        ? 60
                        : i == 1
                        ? 240
                        : 80,
                    minLines: 1,
                    maxLines: i == 1 ? 3 : 2,
                    decoration: InputDecoration(labelText: labels[i]),
                    validator: (s) => s == null || s.trim().isEmpty
                        ? 'Заполните это поле'
                        : null,
                  ),
                ),
            ],
          ),
        ),
        const _Notice(
          'Задание ребёнка появится и в обычном списке заданий. Оформление не меняет порядок проверки результатов.',
        ),
        FilledButton(
          onPressed: c.busy
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  submittedIds = c.state.missions.map((m) => m.id).toSet();
                  submittedFields = fields.map((f) => f.text.trim()).toList();
                  submittedHelper = helperId;
                  submittedOwner = c.currentMemberId;
                  creationAccepted = false;
                  await playAction(context, () async {
                    await c.createMission(
                      title: fields[0].text,
                      description: fields[1].text,
                      reward: fields[2].text,
                      childStep: fields[3].text,
                      parentStep: fields[4].text,
                      helperId: helperId!,
                      helperStep: fields[5].text,
                    );
                    creationAccepted = true;
                  });
                  if (context.mounted) openCreatedMission(c);
                },
          child: const Text('Создать миссию'),
        ),
      ],
    );
  }
}

class AdventureSetupPage extends StatefulWidget {
  const AdventureSetupPage({super.key});
  @override
  State<AdventureSetupPage> createState() => _AdventureSetupPageState();
}

class _AdventureSetupPageState extends State<AdventureSetupPage> {
  List<String>? selected;
  @override
  Widget build(BuildContext context) {
    final c = EngagementScope.of(context);
    selected ??= c.state.adventureTaskIds
        .where((id) => c.tasks.any((task) => task.id == id))
        .toList();
    final tasks = c.tasks;
    final routeOrder = {
      for (final (index, id) in c.state.adventureTaskIds.indexed) id: index,
    };
    final sourceOrder = {
      for (final (index, task) in tasks.indexed) task.id: index,
    };
    // Keep the saved route readable even when the server's row order differs:
    // unfinished route steps, confirmed steps, then other available tasks.
    // Checkbox edits do not reorder rows until the route is saved.
    int group(PlayTask task) =>
        routeOrder.containsKey(task.id) ? (task.completed ? 1 : 0) : 2;
    final orderedTasks = [...tasks]
      ..sort((a, b) {
        final section = group(a).compareTo(group(b));
        if (section != 0) return section;
        return (routeOrder[a.id] ?? sourceOrder[a.id]!).compareTo(
          routeOrder[b.id] ?? sourceOrder[b.id]!,
        );
      });
    return PlayScaffold(
      title: 'Три дела для приключения',
      parentOnly: true,
      children: [
        const _Heading(
          'Знакомые дела — новый маршрут',
          'Выберите три задания ребёнка. Их проверка и награды остаются прежними.',
        ),
        Text(
          'Выбрано ${selected!.length} из 3',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        for (final task in orderedTasks)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(task.title),
            subtitle: Text(
              task.completed
                  ? 'Уже подтверждено'
                  : task.waiting
                  ? 'Ждёт проверки'
                  : 'Можно выполнить',
            ),
            value: selected!.contains(task.id),
            onChanged:
                c.busy ||
                    (!selected!.contains(task.id) && selected!.length == 3)
                ? null
                : (value) => setState(() {
                    value == true
                        ? selected!.add(task.id)
                        : selected!.remove(task.id);
                  }),
          ),
        const _Notice(
          'Открытые предметы сохранятся. После выбора других заданий начнётся новый маршрут.',
        ),
        FilledButton(
          onPressed: c.busy || selected!.length != 3
              ? null
              : () async {
                  await playAction(
                    context,
                    () => c.chooseAdventureTasks(selected!),
                    success: 'Приключение готово',
                  );
                },
          child: const Text('Сохранить приключение'),
        ),
      ],
    );
  }
}
