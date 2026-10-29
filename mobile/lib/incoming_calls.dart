import 'dart:async';

import 'package:flutter/material.dart';

import 'background.dart';
import 'call_screen.dart';
import 'repository.dart';
import 'messenger_widgets.dart';

class FamilyCallNavigation extends NavigatorObserver {
  final _calls = <Route<dynamic>>{};
  bool get inCall => _calls.isNotEmpty;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'family-call') _calls.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _calls.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _calls.remove(route);
}

Future<void> openFamilyCall(
  BuildContext context,
  FamilyRepository repository,
  String id,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'family-call'),
    builder: (_) =>
        CallPresentation.maybeOf(context)?.builder(repository, id) ??
        CallScreen(repository: repository, callId: id),
  ),
);

/// Incoming invitations are shown above any page, independently of notification permission.
class IncomingCallHost extends StatefulWidget {
  final FamilyRepository repository;
  final GlobalKey<NavigatorState> navigatorKey;
  final FamilyCallNavigation navigation;
  final Widget child;
  final Widget Function(String id)? callBuilder;
  const IncomingCallHost({
    super.key,
    required this.repository,
    required this.navigatorKey,
    required this.navigation,
    required this.child,
    this.callBuilder,
  });
  @override
  State<IncomingCallHost> createState() => _IncomingCallHostState();
}

class _IncomingCallHostState extends State<IncomingCallHost>
    with WidgetsBindingObserver {
  bool presenting = false, scheduled = false;
  DialogRoute<String>? invitation;
  String? callId, identity;
  FamilyRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repo.addListener(changed);
    changed();
  }

  bool pending(Map<String, dynamic> call) =>
      ['ringing', 'active'].contains(call['status']) &&
      call['member_status'] == 'invited' &&
      call['caller_id'] != repo.userId;

  void changed() {
    if (scheduled || !mounted) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (mounted) consider();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> ring(bool play) async {
    try {
      await nativeCalls.invokeMethod<void>(play ? 'ring' : 'stopRinging');
    } catch (_) {
      /* The invitation remains visible when sound is unavailable. */
    }
  }

  void consider() {
    final calls = repo.rows('calls').where(pending).toList();
    if (invitation != null &&
        (!repo.signedIn ||
            !repo.online ||
            identity != repo.sessionTag ||
            !calls.any((call) => call['id'] == callId))) {
      final route = invitation!;
      if (route.isActive) route.navigator?.removeRoute(route);
      unawaited(ring(false));
      return;
    }
    if (presenting ||
        !repo.signedIn ||
        !repo.online ||
        calls.isEmpty ||
        widget.navigation.inCall ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    presenting = true;
    unawaited(show(navigator, calls.first));
  }

  Future<void> show(NavigatorState navigator, Map<String, dynamic> call) async {
    final session = repo.sessionTag;
    final id = call['id'] as String;
    identity = session;
    callId = id;
    final route = DialogRoute<String>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => IncomingCallDialog(repository: repo, call: call),
    );
    invitation = route;
    unawaited(ring(true));
    try {
      final answer = await navigator.push(route);
      invitation = null;
      await ring(false);
      if (answer == 'answer' &&
          mounted &&
          repo.signedIn &&
          repo.sessionTag == session &&
          repo.online &&
          repo.rows('calls').any((row) => row['id'] == id && pending(row))) {
        await navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'family-call'),
            builder: (_) =>
                widget.callBuilder?.call(id) ??
                CallScreen(repository: repo, callId: id),
          ),
        );
        if (mounted && repo.signedIn && repo.sessionTag == session) {
          await repo.sync();
        }
      }
    } finally {
      invitation = null;
      presenting = false;
      callId = identity = null;
      unawaited(ring(false));
      if (mounted) changed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (invitation != null) unawaited(ring(true));
      changed();
    } else {
      unawaited(ring(false));
    }
  }

  @override
  void dispose() {
    repo.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ring(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class IncomingCallDialog extends StatefulWidget {
  final FamilyRepository repository;
  final Map<String, dynamic> call;
  const IncomingCallDialog({
    super.key,
    required this.repository,
    required this.call,
  });
  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog> {
  bool busy = false;
  String? error;
  Future<void> decline() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.mutate('/v1/calls/${widget.call['id']}/actions', {
        'action': 'decline',
      });
      if (mounted) Navigator.pop(context, 'declined');
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is ApiFailure
              ? failure.message
              : 'Не удалось отклонить звонок. Попробуйте ещё раз',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caller = widget.repository
        .rows('members')
        .where((m) => m['id'] == widget.call['caller_id'])
        .firstOrNull;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: callBackground,
        titleTextStyle: const TextStyle(color: Colors.white70, fontSize: 16),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 16),
        scrollable: true,
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        title: Text(
          widget.call['video'] == 1
              ? 'Входящий видеозвонок'
              : 'Входящий аудиозвонок',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FamilyAvatar(
              name: caller?['name'] as String? ?? 'Семья',
              size: 96,
              dark: true,
            ),
            const SizedBox(height: 20),
            Text(
              caller?['name'] as String? ?? 'Семья',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'MyKIDS · Семья рядом',
              style: TextStyle(color: Colors.white70),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Color(0xffffd34b)),
                ),
              ),
          ],
        ),
        actions: [
          CallControl(
            label: 'Отклонить',
            icon: Icons.call_end_rounded,
            color: const Color(0xffd93648),
            onPressed: busy ? null : decline,
          ),
          CallControl(
            label: 'Ответить',
            icon: widget.call['video'] == 1
                ? Icons.videocam_rounded
                : Icons.call_rounded,
            color: const Color(0xff1963c5),
            onPressed: busy ? null : () => Navigator.pop(context, 'answer'),
          ),
        ],
      ),
    );
  }
}

/// Optional media source for isolated review. Production keeps CallScreen.
class CallPresentation extends InheritedWidget {
  final Widget Function(FamilyRepository, String) builder;
  const CallPresentation({
    super.key,
    required this.builder,
    required super.child,
  });
  static CallPresentation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CallPresentation>();
  @override
  bool updateShouldNotify(CallPresentation oldWidget) =>
      oldWidget.builder != builder;
}
