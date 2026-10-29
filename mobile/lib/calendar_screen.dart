import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'calendar.dart';
import 'child_visuals.dart';
import 'design_system.dart';
import 'repository.dart';
import 'schedule.dart';
import 'school_screen.dart';
import 'form_layout.dart';
import 'event_editor.dart';
import 'family_action.dart';
import 'event_style.dart';
import 'calendar_grid.dart';
import 'calendar_month.dart';
import 'task_screen.dart';

export 'event_editor.dart';

const calendarMonths = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];

class CalendarTile extends StatelessWidget {
  final CalendarEntry entry;
  final bool conflict, child;
  final VoidCallback? onTap;
  const CalendarTile({
    super.key,
    required this.entry,
    this.conflict = false,
    this.child = false,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Card(
    color: eventBackground(entry),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.timeText,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                if (child)
                  ChildArt(
                    entry.kind == 'school' || entry.kind == 'homework'
                        ? 0
                        : entry.kind == 'free'
                        ? 3
                        : 1,
                    size: 48,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(entry.title, style: Theme.of(context).textTheme.titleLarge),
            if (entry.place.isNotEmpty) Text(entry.place),
            if (entry.note.isNotEmpty) Text(entry.note),
            EventActivities(activities: entry.activities),
            if (entry.deadline)
              const Text('Срок выполнения; время занятия не задано'),
            if (conflict)
              const Text(
                'Пересекается с другим занятием',
                style: TextStyle(
                  color: Color(0xff942b20),
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (entry.reminder != null)
              Text(
                entry.reminder == 0
                    ? 'Напоминание в начале'
                    : 'Напоминание за ${entry.reminder} мин.',
              ),
          ],
        ),
      ),
    ),
  );
}

class CalendarScreen extends StatefulWidget {
  final FamilyRepository repository;
  final Future<void> Function(Future<Map<String, dynamic>> Function()) perform;
  final DateTime? initialDay;
  final String initialMode;
  final void Function(DateTime day, String mode)? onSelectionChanged;
  final ValueChanged<DateTime> openTasks;
  const CalendarScreen({
    super.key,
    required this.repository,
    required this.perform,
    required this.openTasks,
    this.initialDay,
    this.initialMode = 'День',
    this.onSelectionChanged,
  }) : assert(
         initialMode == 'День' ||
             initialMode == 'Неделя' ||
             initialMode == 'Месяц',
       );
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  FamilyRepository get repo => widget.repository;
  late tz.TZDateTime day;
  late String mode;
  bool _interactionOpen = false;
  FamilyActionAccess? _activeAccess, _viewAccess;

  FamilyActionAccess captureViewAccess() {
    if (_viewAccess == null || !_viewAccess!.valid) {
      _viewAccess?.dispose();
      final owner = repo;
      _viewAccess = FamilyActionAccess(
        owner,
        permitted: () => mounted && identical(repo, owner),
      );
    }
    return _viewAccess!;
  }

  void refresh() {
    // Observe transient changes before a following notification restores access.
    if (_activeAccess?.valid == false) _activeAccess?.invalidate();
    if (_viewAccess?.valid == false) _viewAccess?.invalidate();
    if (mounted) setState(() {});
  }

  bool current(FamilyActionAccess access) =>
      mounted && access.valid && ModalRoute.of(context)?.isCurrent == true;

  Future<void> interact(
    Future<void> Function(FamilyRepository, FamilyActionAccess) action,
  ) async {
    if (_interactionOpen ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final owner = repo;
    final access = FamilyActionAccess(
      owner,
      permitted: () => mounted && identical(repo, owner),
    );
    if (!access.valid) {
      access.dispose();
      return;
    }
    _interactionOpen = true;
    _activeAccess = access;
    try {
      await action(owner, access);
    } finally {
      _interactionOpen = false;
      _activeAccess = null;
      access.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    day = familyClock(repo.snapshot, widget.initialDay);
    mode = widget.initialMode;
    repo.addListener(refresh);
  }

  @override
  void didUpdateWidget(CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, repo)) {
      _activeAccess?.invalidate();
      _viewAccess?.invalidate();
      oldWidget.repository.removeListener(refresh);
      repo.addListener(refresh);
    }
    final location = familyClock(repo.snapshot).location;
    if (day.location.name != location.name) {
      // A family timezone change must keep the selected civil date.
      day = tz.TZDateTime(location, day.year, day.month, day.day);
    }
    if (widget.initialMode != oldWidget.initialMode) {
      mode = widget.initialMode;
    }
    if (widget.initialDay != null &&
        widget.initialDay != oldWidget.initialDay) {
      final focused = familyClock(repo.snapshot, widget.initialDay);
      // A parent remembering our selection is not a new navigation request.
      if (dateOnly(focused) != dateOnly(day)) {
        day = focused;
        mode = widget.initialMode;
      }
    }
  }

  @override
  void dispose() {
    _activeAccess?.invalidate();
    _viewAccess?.dispose();
    repo.removeListener(refresh);
    super.dispose();
  }

  void select(DateTime value, {String? view}) {
    setState(() {
      day = tz.TZDateTime(day.location, value.year, value.month, value.day);
      if (view != null) mode = view;
    });
    widget.onSelectionChanged?.call(day, mode);
  }

  void shift(int direction) {
    select(switch (mode) {
      'Неделя' => tz.TZDateTime(
        day.location,
        day.year,
        day.month,
        day.day + 7 * direction,
      ),
      'Месяц' => tz.TZDateTime(
        day.location,
        day.year,
        day.month + direction,
        1,
      ),
      _ => tz.TZDateTime(
        day.location,
        day.year,
        day.month,
        day.day + direction,
      ),
    });
  }

  Future<void> edit([
    CalendarEntry? entry,
    bool single = false,
    TimeOfDay? initialStart,
  ]) => interact(
    (owner, access) => editCaptured(owner, access, entry, single, initialStart),
  );

  Future<void> editCaptured(
    FamilyRepository owner,
    FamilyActionAccess access,
    CalendarEntry? entry,
    bool single, [
    TimeOfDay? initialStart,
  ]) async {
    if (!current(access) || owner.role != 'parent') return;
    final selectedDay = entry?.start ?? day;
    // Keep the revision seen when opening this editor, even if a foreground
    // refresh replaces the shared snapshot while the parent is typing.
    final initial = entry == null
        ? null
        : Map<String, dynamic>.from(
            single
                ? entry.source!
                : owner
                      .rows('schedules')
                      .firstWhere((row) => row['id'] == entry.source!['id']),
          );
    final revision = initial?['revision'];
    final snapshot = owner.snapshot!;
    final route = MaterialPageRoute<Map<String, dynamic>>(
      builder: (_) => CalendarEditor(
        snapshot: snapshot,
        access: access,
        day: selectedDay,
        initial: initial,
        single: single,
        initialStart: initialStart,
        onSave: (body) {
          access.requireCurrent();
          if (owner.role != 'parent') {
            throw ApiFailure(403, 'Изменять календарь может только родитель');
          }
          return owner.mutate(
            entry == null
                ? '/v1/schedules'
                : single
                ? '/v1/schedules/${entry.source!['id']}/exceptions'
                : '/v1/schedules/${entry.source!['id']}',
            single
                ? {
                    'date': dateOnly(selectedDay),
                    'replacement': body,
                    'expected_revision': ?revision,
                  }
                : {...body, 'expected_revision': ?revision},
            method: entry != null && !single ? 'PUT' : 'POST',
            offlineSubmission: true,
          );
        },
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
  }

  Future<void> entryActions(CalendarEntry entry) => interact((
    owner,
    access,
  ) async {
    if (entry.key.startsWith('task:')) {
      await openCalendarTask(
        context,
        owner,
        widget.perform,
        entry.source!['id'] as String,
        entry.start,
      );
      return;
    }
    CalendarEntry? currentEntry() {
      if (!access.valid) return null;
      return calendarDay(
        owner.snapshot!,
        entry.start,
      ).where((item) => item.key == entry.key).firstOrNull;
    }

    bool repeats(CalendarEntry item) => owner
        .rows('schedules')
        .any((row) => row['id'] == item.source?['id'] && row['date'] == null);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FamilyActionDialog<String>(
        access: access,
        allowOffline: true,
        builder: (context, close) {
          final current = currentEntry();
          final recurring = current != null && repeats(current);
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: spacedFormItems([
                  if (current == null) ...[
                    const Text('На этот день событие отменено или перенесено'),
                    FilledButton(
                      onPressed: () => close(null),
                      child: const Text('Закрыть'),
                    ),
                  ] else
                    CalendarTile(entry: current),
                  if (current != null && owner.role == 'parent') ...[
                    FilledButton(
                      onPressed: () => close('all'),
                      child: Text(
                        recurring
                            ? 'Изменить событие и повторения'
                            : 'Изменить событие',
                      ),
                    ),
                    if (recurring)
                      OutlinedButton(
                        onPressed: () => close('one'),
                        child: const Text('Изменить только этот день'),
                      ),
                    if (recurring)
                      TextButton(
                        onPressed: () => close('cancel'),
                        child: const Text('Отменить только этот день'),
                      ),
                    TextButton(
                      onPressed: () => close('delete'),
                      child: Text(
                        recurring
                            ? 'Удалить событие и повторения'
                            : 'Удалить событие',
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          );
        },
      ),
    );
    if (action == null ||
        !mounted ||
        !current(access) ||
        owner.role != 'parent') {
      return;
    }
    final latest = currentEntry();
    if (latest == null) return;
    entry = latest;
    final recurring = repeats(entry);
    if (action == 'one' || action == 'all') {
      await editCaptured(owner, access, entry, action == 'one');
    } else {
      final confirmation = DialogRoute<bool>(
        context: context,
        builder: (context) => FamilyActionDialog<bool>(
          access: access,
          allowOffline: true,
          builder: (context, close) => AlertDialog(
            scrollable: true,
            title: Text(
              action == 'cancel'
                  ? 'Отменить на ${calendarDateLabel(entry.start)}?'
                  : recurring
                  ? 'Удалить событие и повторения?'
                  : 'Удалить событие?',
            ),
            content: Text(
              currentEntry()?.title ?? 'Событие уже отменено или перенесено',
            ),
            actions: [
              TextButton(
                onPressed: () => close(false),
                child: const Text('Назад'),
              ),
              FilledButton(
                onPressed: currentEntry() == null ? null : () => close(true),
                child: const Text('Подтвердить'),
              ),
            ],
          ),
        ),
      );
      try {
        final yes = await Navigator.of(
          context,
          rootNavigator: true,
        ).push(confirmation);
        if (yes != true || !current(access) || owner.role != 'parent') return;
        if (currentEntry() == null) return;
        await widget.perform(() {
          access.requireCurrent();
          if (!current(access) || owner.role != 'parent') {
            throw ApiFailure(403, 'Откройте событие заново');
          }
          return owner.mutate(
            '/v1/schedules/${entry.source!['id']}${action == 'cancel' ? '/exceptions' : ''}',
            {
              if (action == 'cancel') 'date': dateOnly(entry.start),
              if (entry.source?['revision'] != null)
                'expected_revision': entry.source!['revision'],
            },
            method: action == 'cancel' ? 'POST' : 'DELETE',
            offlineSubmission: true,
          );
        });
      } finally {
        // Keep the captured owner alive until the closing frame is gone.
        await confirmation.completed;
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = repo.snapshot;
    if (snapshot == null) {
      return const Center(
        child: Text('Семейный доступ изменился. Откройте календарь заново.'),
      );
    }
    final viewAccess = captureViewAccess();
    final cache = <String, List<CalendarEntry>>{};
    List<CalendarEntry> events(DateTime value) =>
        cache.putIfAbsent(dateOnly(value), () => calendarDay(snapshot, value));
    void open(CalendarEntry entry) {
      if (!current(viewAccess) || _interactionOpen) return;
      select(entry.start);
      entryActions(entry);
    }

    final weekStart = tz.TZDateTime(
      day.location,
      day.year,
      day.month,
      day.day - day.weekday + 1,
    );
    return ColoredBox(
      color: gameDesign.value?.background ?? Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: spacedFormItems([
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    'Календарь',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (repo.role == 'parent')
                    FilledButton.icon(
                      onPressed: () {
                        if (current(viewAccess)) edit();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить событие'),
                    ),
                ],
              ),
              if (repo.db != null)
                FutureBuilder<List<Map<String, Object?>>>(
                  future: repo.pending(),
                  builder: (context, result) {
                    final changes = (result.data ?? [])
                        .where(
                          (row) =>
                              (row['path'] as String).startsWith(
                                '/v1/schedules',
                              ) ||
                              (row['path'] as String).endsWith('/plan'),
                        )
                        .toList();
                    if (changes.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Изменений ожидают сверки: ${changes.length}. Пока показано сохранённое расписание.',
                          ),
                          for (final row in changes.where(
                            (row) => row['state'] == 'failed',
                          ))
                            Text(
                              'Изменение не применено: ${row['error']}',
                              style: const TextStyle(color: Color(0xff942b20)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
          if (!repo.online)
            const Text(
              'Сохранённое расписание; изменения появятся после подключения и сверки',
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final view in ['День', 'Неделя', 'Месяц'])
                ChoiceChip(
                  label: Text(view),
                  selected: mode == view,
                  onSelected: (_) => select(day, view: view),
                ),
            ],
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Предыдущий период',
                onPressed: () => shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (mounted && picked != null) select(picked);
                  },
                  child: Text(
                    mode == 'Месяц'
                        ? '${calendarMonths[day.month - 1]} ${day.year}'
                        : mode == 'Неделя'
                        ? '${calendarDateLabel(weekStart)} — ${calendarDateLabel(tz.TZDateTime(day.location, weekStart.year, weekStart.month, weekStart.day + 6))}'
                        : calendarDateLabel(day),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Следующий период',
                onPressed: () => shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => select(familyClock(snapshot)),
              child: const Text('Сегодня'),
            ),
          ),
          if (mode == 'Месяц') ...[
            CalendarMonth(
              selected: day,
              entries: events,
              select: (value) => select(value),
            ),
            Text(
              calendarDateLabel(day),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (events(day).isEmpty) const Text('На этот день событий нет'),
            for (final entry in events(day))
              CalendarTile(
                entry: entry,
                conflict: calendarConflicts(events(day)).contains(entry.key),
                onTap: () => open(entry),
              ),
          ] else if (gameDesign.value != null && mode == 'День') ...[
            if (events(day).isEmpty) const Text('На этот день событий нет'),
            for (final entry in events(day))
              CalendarTile(
                entry: entry,
                conflict: calendarConflicts(events(day)).contains(entry.key),
                onTap: () => open(entry),
              ),
          ] else ...[
            if (mode == 'День' && events(day).isEmpty)
              const Text('На этот день событий нет'),
            if (mode == 'Неделя')
              const Text(
                'Проведите влево или вправо, чтобы увидеть остальные дни',
              ),
            CalendarTimeline(
              days: mode == 'День'
                  ? [day]
                  : [
                      for (var i = 0; i < 7; i++)
                        tz.TZDateTime(
                          day.location,
                          weekStart.year,
                          weekStart.month,
                          weekStart.day + i,
                        ),
                    ],
              entries: events,
              open: open,
              create: repo.role == 'parent'
                  ? (date, time) {
                      if (!current(viewAccess) || _interactionOpen) return;
                      select(date);
                      edit(null, false, time);
                    }
                  : null,
            ),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => widget.openTasks(day),
                child: const Text('Семейные задания'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SchoolScreen(
                      repository: repo,
                      perform: widget.perform,
                      gradesOnly: true,
                      initialDay: day,
                    ),
                  ),
                ),
                child: const Text('Предметы и оценки'),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}
