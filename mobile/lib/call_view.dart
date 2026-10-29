import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'messenger_widgets.dart';

class CallPerson {
  final String name;
  final bool local;
  final Widget? video;
  const CallPerson({required this.name, this.local = false, this.video});
}

/// The presentation is independent of media transport so it can be checked at
/// small sizes and with large text without opening cameras or microphones.
class FamilyCallView extends StatefulWidget {
  final String title, status;
  final List<CallPerson> people;
  final List<Widget> controls;
  final VoidCallback onClose;
  final Future<void> Function(WidgetBuilder builder)? openControls;
  const FamilyCallView({
    super.key,
    required this.title,
    required this.status,
    required this.people,
    required this.controls,
    required this.onClose,
    this.openControls,
  });

  @override
  State<FamilyCallView> createState() => _FamilyCallViewState();
}

class _FamilyCallViewState extends State<FamilyCallView> {
  final controlRevision = ValueNotifier<int>(0);
  bool optionsOpen = false, refreshQueued = false;
  String get title => widget.title;
  String get status => widget.status;
  List<CallPerson> get people => widget.people;
  List<Widget> get controls => widget.controls;
  VoidCallback get onClose => widget.onClose;

  @override
  void didUpdateWidget(covariant FamilyCallView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!optionsOpen || refreshQueued) return;
    refreshQueued = true;
    // The sheet is a separate route. Refresh it after the call's new frame,
    // so connection and permission changes cannot leave captured old controls.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshQueued = false;
      if (mounted && optionsOpen) controlRevision.value++;
    });
  }

  @override
  void dispose() {
    controlRevision.dispose();
    super.dispose();
  }

  Future<void> options(BuildContext context) async {
    if (optionsOpen) return;
    optionsOpen = true;
    Widget builder(BuildContext sheetContext) => ValueListenableBuilder<int>(
      valueListenable: controlRevision,
      builder: (_, revision, child) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 16,
            children: [
              for (final item in controls.skip(2))
                if (item is CallControl)
                  CallControl(
                    label: item.label,
                    icon: item.icon,
                    selected: item.selected,
                    color: item.color,
                    tooltip: item.tooltip,
                    onPressed: item.onPressed == null
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            item.onPressed!();
                          },
                  )
                else
                  item,
            ],
          ),
        ),
      ),
    );
    try {
      await (widget.openControls?.call(builder) ??
          showModalBottomSheet<void>(
            context: context,
            backgroundColor: gameCallBackground,
            builder: builder,
          ));
    } finally {
      optionsOpen = false;
    }
  }

  Widget stage(BuildContext context) {
    final remote = people.where((person) => !person.local).toList();
    final local = people.where((person) => person.local).firstOrNull;
    final shown = remote.isNotEmpty ? remote : people;
    if (shown.length <= 1) {
      final person = shown.firstOrNull ?? CallPerson(name: title);
      return Stack(
        fit: StackFit.expand,
        children: [
          _PersonStage(person: person, showName: false),
          if (remote.isNotEmpty && local?.video != null)
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + 12,
              right: 12,
              width: 104,
              height: 148,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: _PersonStage(person: local!),
              ),
            ),
        ],
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 112, 12, 160),
      itemCount: people.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        childAspectRatio: .8,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (_, i) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: _PersonStage(person: people[i]),
      ),
    );
  }

  Widget buttons(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
    child: Row(
      children: [
        for (final control in controls.take(2)) Expanded(child: control),
        Expanded(
          child: CallControl(
            label: 'Завершить',
            icon: Icons.call_end_rounded,
            color: const Color(0xffd93648),
            onPressed: onClose,
          ),
        ),
        if (controls.length > 2)
          Expanded(
            child: CallControl(
              label: 'Ещё',
              icon: Icons.more_horiz_rounded,
              onPressed: () => options(context),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: gameCallBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            key: const ValueKey('call-fullscreen-stage'),
            child: stage(context),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 140, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        status,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: SafeArea(top: false, child: buttons(context)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PersonStage extends StatelessWidget {
  final CallPerson person;
  final bool showName;
  const _PersonStage({required this.person, this.showName = true});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: gameCallBackground,
    child: Stack(
      fit: StackFit.expand,
      children: [
        person.video ??
            Center(
              child: FamilyAvatar(name: person.name, size: 112, dark: true),
            ),
        if (showName)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Text(
              person.local ? 'Вы' : person.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
      ],
    ),
  );
}
