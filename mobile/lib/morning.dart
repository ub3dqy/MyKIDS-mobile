import 'dart:async';

import 'package:flutter/material.dart';

import 'calendar.dart';
import 'event_style.dart';
import 'child_visuals.dart';
import 'visuals.dart';

/// Authored ImageGen strips; each activity has its own row of four poses.
class CalendarMotion extends StatefulWidget {
  final String kind;
  const CalendarMotion({super.key, required this.kind});
  @override
  State<CalendarMotion> createState() => _CalendarMotionState();
}

class _CalendarMotionState extends State<CalendarMotion>
    with WidgetsBindingObserver {
  Timer? timer;
  Animation<double>? entryAnimation;
  AnimationStatusListener? entryListener;
  int artworkRequest = 0;
  int tick = 0;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void configure() {
    timer?.cancel();
    final request = ++artworkRequest;
    clearEntryWaiter();
    if (!foreground ||
        !TickerMode.valuesOf(context).enabled ||
        MediaQuery.disableAnimationsOf(context)) {
      tick = 0;
      return;
    }
    if (widget.kind == 'free' || widget.kind == 'other') return;
    if (!rasterArtworkIsReady(artworkPath)) {
      unawaited(startAfterArtwork(artworkPath, request));
      return;
    }
    startAfterEntry(request);
  }

  String get strip => widget.kind == 'school' || widget.kind == 'homework'
      ? 'book'
      : widget.kind == 'extra'
      ? 'extra'
      : 'task';

  String get artworkPath => 'assets/generated/calendar-$strip.png';

  void startTimer(int request) {
    timer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || request != artworkRequest) return;
      setState(() => tick = (tick + 1) % 14);
      // A delayed UI frame must still show this pose before the next one.
      // Periodic wall-clock ticks could advance several poses before painting.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && request == artworkRequest) startTimer(request);
      });
    });
  }

  void clearEntryWaiter() {
    final listener = entryListener;
    if (listener != null) entryAnimation?.removeStatusListener(listener);
    entryAnimation = null;
    entryListener = null;
  }

  void startAfterEntry(int request) {
    if (!mounted || request != artworkRequest) return;
    void afterPaint() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && request == artworkRequest) startTimer(request);
      });
    }

    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      afterPaint();
      return;
    }
    // A painted image can still be hidden by the entering dialog's opacity.
    // Keep its first pose until the route is visible, then paint before moving.
    entryAnimation = animation;
    entryListener = (status) {
      if (!mounted || request != artworkRequest) return;
      if (status == AnimationStatus.completed) {
        clearEntryWaiter();
        afterPaint();
      }
    };
    animation.addStatusListener(entryListener!);
  }

  Future<void> startAfterArtwork(String path, int request) async {
    try {
      await precacheRasterArtwork([path]);
    } catch (error, stack) {
      if (mounted && request == artworkRequest) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'MyKIDS morning artwork',
          ),
        );
      }
      return;
    }
    if (!mounted || request != artworkRequest) return;
    setState(() => tick = 0);
    startAfterEntry(request);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    configure();
  }

  @override
  void didUpdateWidget(CalendarMotion old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind) {
      tick = 0;
      configure();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (mounted) {
      configure();
      setState(() {});
    }
  }

  @override
  void dispose() {
    artworkRequest++;
    timer?.cancel();
    clearEntryWaiter();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == 'free' || widget.kind == 'other') {
      return const ChildMotion(size: 130);
    }
    final frame = MediaQuery.disableAnimationsOf(context)
        ? 0
        : tick < 4
        ? tick
        : 3;
    // Open arms need wider gutters; the adjacent frames exclude those pixels.
    const extraEdges = [0.0, 384.0, 730.0, 1190.0, 1536.0];
    final left = strip == 'extra' ? extraEdges[frame] / 1536 : frame / 4;
    final width = strip == 'extra'
        ? (extraEdges[frame + 1] - extraEdges[frame]) / 1536
        : .25;
    return Semantics(
      label: 'Помощник: ${calendarKinds[widget.kind]}',
      image: true,
      child: RasterSprite(
        path: artworkPath,
        normalized: true,
        source: Rect.fromLTWH(left, .1, width, .82),
        preserveAspectRatio: true,
        size: 130,
      ),
    );
  }
}

class MorningOverview extends StatefulWidget {
  final List<CalendarEntry> entries;
  final String dayLabel;
  final bool online;
  final bool hasConflicts;
  final List<String> preparations;
  const MorningOverview({
    super.key,
    required this.entries,
    required this.dayLabel,
    this.online = true,
    this.hasConflicts = false,
    this.preparations = const [],
  });
  @override
  State<MorningOverview> createState() => _MorningOverviewState();
}

class _MorningOverviewState extends State<MorningOverview> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final entry = widget.entries.isEmpty ? null : widget.entries[index];
    return AlertDialog(
      title: Text('Твой день · ${widget.dayLabel}'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.online) const Text('По сохранённому расписанию'),
          if (widget.preparations.isNotEmpty) ...[
            const Text(
              'Подготовь на сегодня',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final message in widget.preparations)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('• $message'),
              ),
            const SizedBox(height: 12),
          ],
          if (widget.hasConflicts)
            const Text(
              'Некоторые дела пересекаются. Проверь весь день с семьёй.',
              style: TextStyle(color: Color(0xff942b20)),
            ),
          if (entry == null) ...[
            const Center(child: ChildMotion(size: 130)),
            const Text(
              'Расписание пока пустое. Когда семья добавит дела, я расскажу о них здесь.',
            ),
          ] else ...[
            Center(
              child: CalendarMotion(key: ValueKey(entry.key), kind: entry.kind),
            ),
            Text(
              '${index + 1} из ${widget.entries.length}',
              textAlign: TextAlign.center,
            ),
            LinearProgressIndicator(value: (index + 1) / widget.entries.length),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Column(
                key: ValueKey(entry.key),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    entry.timeText,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (entry.note.isNotEmpty)
                    Text(
                      entry.note,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  EventActivities(activities: entry.activities),
                  if (entry.place.isNotEmpty) Text(entry.place),
                  if (entry.deadline)
                    const Text(
                      'Это срок задания. Время работы ещё не назначено.',
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (index > 0)
          TextButton(
            onPressed: () => setState(() => index--),
            child: const Text('Назад'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Весь день'),
        ),
        FilledButton(
          onPressed: () {
            if (index + 1 < widget.entries.length) {
              setState(() => index++);
            } else {
              Navigator.pop(context, false);
            }
          },
          child: Text(
            entry == null || index + 1 == widget.entries.length
                ? 'Понятно!'
                : 'Дальше',
          ),
        ),
      ],
    );
  }
}
