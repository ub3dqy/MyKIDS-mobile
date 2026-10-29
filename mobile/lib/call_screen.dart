import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'background.dart';
import 'call_view.dart';
import 'messenger_widgets.dart';
import 'repository.dart';
import 'family_contacts.dart';

class CallScreen extends StatefulWidget {
  final FamilyRepository repository;
  final String callId;
  @visibleForTesting
  final Room? testRoom;
  @visibleForTesting
  final Future<void> Function(bool preferred, bool force)? testSpeakerRouting;
  const CallScreen({
    super.key,
    required this.repository,
    required this.callId,
    this.testRoom,
    this.testSpeakerRouting,
  });
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static String? activeOwner;
  final owner = const Uuid().v4();
  late final Future<void> nativeClaim;
  Map<String, dynamic> get callScope => {'owner': owner, 'id': widget.callId};
  Future<void> startNativeService(bool video) =>
      nativeCalls.invokeMethod('start', {...callScope, 'video': video});
  late final Room room;
  late final EventsListener<RoomEvent> events;
  String status = 'Подключение…';
  bool connected = false,
      microphone = true,
      camera = false,
      cameraUnavailable = false,
      speaker = false,
      front = true;
  bool closing = false, controlling = false;
  Future<void>? connection;
  Future<void> routeSpeaker(bool preferred, {bool force = false}) =>
      widget.testSpeakerRouting?.call(preferred, force) ??
      AudioManager.instance.setSpeakerOutputPreferred(preferred, force: force);
  Route<dynamic>? inviteSheet;
  final controlSheets = <Route<dynamic>>{};
  FamilyRepository get repo => widget.repository;
  @override
  void initState() {
    super.initState();
    activeOwner = owner;
    nativeClaim = nativeCalls.invokeMethod('claimCall', callScope);
    room =
        widget.testRoom ??
        Room(
          roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
        );
    room.addListener(changed);
    events = room.createListener()
      ..on<RoomDisconnectedEvent>((event) {
        if (connected && !closing) {
          unawaited(close(remote: true));
        }
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        if (connected &&
            !closing &&
            room.remoteParticipants.isEmpty &&
            reservedPeople.length <= 2) {
          unawaited(close());
        }
      });
    repo.addListener(accessChanged);
    connection = connect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && activeOwner == owner) {
        unawaited(
          nativeCalls
              .invokeMethod('revealIncoming', callScope)
              .catchError((_) {}),
        );
      }
    });
    unawaited(connection);
  }

  void accessChanged() {
    if (!repo.signedIn) {
      unawaited(close(remote: true));
    } else if (currentCall?['status'] == 'ended' ||
        [
          'left',
          'declined',
          'missed',
          'revoking',
        ].contains(currentCall?['member_status'])) {
      unawaited(close(remote: true));
    } else if (mounted) {
      setState(() {});
    }
  }

  void ensureOpen() {
    if (closing || !mounted || !repo.signedIn || activeOwner != owner) {
      throw StateError('Звонок закрыт');
    }
  }

  void changed() {
    if (mounted) {
      setState(
        () => status =
            {
              ConnectionState.connected: cameraUnavailable
                  ? 'Соединение установлено. Камера недоступна — можно говорить без видео'
                  : 'Соединение установлено',
              ConnectionState.reconnecting: 'Восстанавливаем соединение',
              ConnectionState.disconnected: 'Соединение завершено',
            }[room.connectionState] ??
            'Подключение…',
      );
    }
  }

  Future<void> connect() async {
    try {
      await nativeClaim;
      ensureOpen();
      if (!await callPermission(Permission.microphone)) {
        throw ApiFailure(
          403,
          'Разрешите микрофон для звонка один раз на разблокированном телефоне',
        );
      }
      ensureOpen();
      await nativeCalls.invokeMethod('dismissIncoming', {'id': widget.callId});
      await repo.mutate('/v1/calls/${widget.callId}/actions', {
        'action': 'join',
      });
      ensureOpen();
      final access = await repo.request(
        '/v1/calls/${widget.callId}/token',
        method: 'POST',
      );
      ensureOpen();
      final videoRequested = access['video'] == true;
      camera = videoRequested && await callPermission(Permission.camera);
      cameraUnavailable = videoRequested && !camera;
      ensureOpen();
      // LiveKit owns audio routing; changing only WebRTC's audio switch is
      // overwritten when LiveKit starts or updates its audio session.
      speaker = videoRequested;
      await routeSpeaker(speaker);
      ensureOpen();
      await startNativeService(false);
      ensureOpen();
      await room.connect(access['url'] as String, access['token'] as String);
      ensureOpen();
      await room.localParticipant?.setMicrophoneEnabled(true);
      ensureOpen();
      var videoAvailable = camera;
      if (camera) {
        try {
          await startNativeService(true);
          ensureOpen();
          await room.localParticipant?.setCameraEnabled(true);
        } catch (failure) {
          ensureOpen();
          unawaited(
            nativeCalls
                .invokeMethod('reportCallFailure', {
                  'stage': 'camera_enable',
                  'code': failure.runtimeType.toString(),
                })
                .catchError((_) {}),
          );
          videoAvailable = false;
          cameraUnavailable = true;
          camera = false;
          try {
            await room.localParticipant?.setCameraEnabled(false);
          } catch (_) {
            for (final publication
                in room.localParticipant?.videoTrackPublications ??
                    <LocalTrackPublication>[]) {
              await publication.track?.stop();
            }
          }
          ensureOpen();
          await startNativeService(false);
        }
      }
      ensureOpen();
      if (mounted) {
        setState(() {
          connected = true;
          status = videoRequested && !videoAvailable
              ? 'Соединение установлено. Камера недоступна — можно говорить без видео'
              : 'Соединение установлено';
        });
      }
    } catch (error) {
      await stopLocalCall();
      if (mounted && !closing) {
        setState(
          () => status = error is ApiFailure
              ? error.message
              : 'Не удалось подключиться к семейному звонку',
        );
      }
    }
  }

  Future<bool> callPermission(Permission permission) async {
    bool locked = false;
    try {
      locked = await nativeCalls.invokeMethod<bool>('deviceLocked') ?? false;
    } catch (_) {}
    // A first permission request belongs in setup, never behind a PIN prompt.
    return locked
        ? await permission.status.isGranted
        : await permission.request().isGranted;
  }

  Future<void> close({bool remote = false}) async {
    if (closing) return;
    closing = true;
    final sheet = inviteSheet;
    inviteSheet = null;
    if (mounted && sheet != null && sheet.isActive) {
      Navigator.of(context).removeRoute(sheet);
    }
    if (mounted) {
      for (final sheet in controlSheets.toList()) {
        if (sheet.isActive) Navigator.of(context).removeRoute(sheet);
      }
      controlSheets.clear();
    }
    // Tell the other endpoint immediately, while local media is being stopped.
    // A slow media disconnection must not delay the server's hang-up action.
    final leaving = remote
        ? Future<void>.value()
        : repo
              .mutate('/v1/calls/${widget.callId}/actions', {'action': 'leave'})
              .then<void>((_) {})
              .catchError((_) {});
    await Future.wait([
      stopLocalCall().timeout(
        const Duration(seconds: 5),
        onTimeout: stopNativeService,
      ),
      leaving.timeout(const Duration(seconds: 5), onTimeout: () {}),
    ]);
    if (mounted) {
      bool nativeFinished = false;
      try {
        nativeFinished =
            await nativeCalls.invokeMethod<bool>(
              'finishCallScreen',
              callScope,
            ) ??
            false;
      } catch (_) {
        // Test hosts and other platforms use Flutter navigation.
      }
      if (nativeFinished || !mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    }
  }

  Future<void> control(Future<void> Function() action) async {
    if (controlling || closing) return;
    setState(() => controlling = true);
    try {
      ensureOpen();
      await action();
      ensureOpen();
      if (mounted) setState(() {});
    } catch (error) {
      if (closing || !mounted || !repo.signedIn) {
        await stopLocalCall();
      } else {
        setState(
          () => status = error is ApiFailure
              ? error.message
              : 'Не удалось изменить настройку звонка',
        );
      }
    } finally {
      if (mounted) setState(() => controlling = false);
    }
  }

  @override
  void dispose() {
    closing = true;
    if (activeOwner == owner) activeOwner = null;
    repo.removeListener(accessChanged);
    room.removeListener(changed);
    unawaited(events.dispose());
    unawaited(disposeRoom());
    unawaited(stopNativeService());
    super.dispose();
  }

  Future<void> disposeRoom() async {
    await connection;
    await stopLocalCall();
    await room.dispose();
  }

  Future<void> stopNativeService() async {
    try {
      await nativeCalls.invokeMethod('stop', callScope);
    } catch (_) {
      // Media tracks are stopped separately; a platform error cannot skip them.
    }
  }

  Future<void> stopLocalCall() async {
    final tracks =
        room.localParticipant?.trackPublications.values
            .map((publication) => publication.track)
            .whereType<LocalTrack>()
            .toList() ??
        <LocalTrack>[];
    for (final track in tracks) {
      try {
        await track.stop();
      } catch (_) {
        try {
          await track.mediaStreamTrack.stop();
        } catch (_) {
          // Continue stopping other tracks and the native service.
        }
      }
    }
    await stopNativeService();
    try {
      await room.disconnect();
    } catch (_) {
      // Disconnect can time out while waiting for the network. Local capture
      // and the foreground service have already been stopped.
    }
  }

  Map<String, dynamic>? get currentCall =>
      repo.rows('calls').where((c) => c['id'] == widget.callId).firstOrNull;
  Set<String> get reservedPeople => {
    ...reservedCallParticipants(currentCall),
    repo.userId,
    ...room.remoteParticipants.values.map((p) => p.identity),
  };

  Future<void> openControls(WidgetBuilder builder) async {
    if (closing || !mounted || activeOwner != owner) return;
    final navigator = Navigator.of(context);
    final route = ModalBottomSheetRoute<void>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).scrimLabel,
      backgroundColor: callBackground,
      isScrollControlled: false,
    );
    controlSheets.add(route);
    await navigator.push(route);
    controlSheets.remove(route);
  }

  Future<void> inviteParticipant() async {
    if (closing || !mounted || !repo.signedIn) return;
    final identity = repo.sessionTag;
    final navigator = Navigator.of(context);
    final localizations = MaterialLocalizations.of(context);
    final sheet = ModalBottomSheetRoute<String>(
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      isScrollControlled: true,
      builder: (context) {
        return AnimatedBuilder(
          animation: Listenable.merge([repo, room]),
          builder: (context, _) {
            final reserved = reservedPeople;
            final contacts = familyContacts(repo)
                .where((m) => !reserved.contains(m['id']))
                .toList();
            final full = reserved.length >= 4;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Пригласить в конференцию',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Участники: ${reserved.length} из 4'),
                    if (contacts.isEmpty || full)
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          full
                              ? 'В конференции уже четыре участника'
                              : 'Все доступные участники уже приглашены',
                        ),
                      ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final contact in contacts)
                            ListTile(
                              leading: FamilyAvatar(
                                name: contact['name'] as String,
                              ),
                              title: Text(contact['name'] as String),
                              onTap: full
                                  ? null
                                  : () => Navigator.pop(
                                      context,
                                      contact['id'] as String,
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    // Register ownership before push: access can be revoked before the first frame.
    inviteSheet = sheet;
    final selected = await navigator.push(sheet);
    if (identical(inviteSheet, sheet)) inviteSheet = null;
    if (selected != null && mounted && repo.sessionTag == identity) {
      await control(() async {
        await repo.mutate('/v1/calls/${widget.callId}/actions', {
          'action': 'invite',
          'user_id': selected,
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final participants = <Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];
    final call = repo
        .rows('calls')
        .where((c) => c['id'] == widget.callId)
        .firstOrNull;
    final title =
        repo
                .rows('rooms')
                .where((r) => r['id'] == call?['room_id'])
                .firstOrNull?['contact']?['name']
            as String? ??
        repo
                .rows('members')
                .where(
                  (m) =>
                      m['id'] == call?['caller_id'] && m['id'] != repo.userId,
                )
                .firstOrNull?['name']
            as String? ??
        'Семейный звонок';
    final enabled =
        connected &&
        !controlling &&
        !closing &&
        room.connectionState == ConnectionState.connected;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(close());
      },
      child: FamilyCallView(
        openControls: openControls,
        title: title,
        status: '$status · ${reservedPeople.length} из 4',
        people: [
          for (final participant in participants)
            CallPerson(
              name: participant.name.isEmpty ? 'Семья' : participant.name,
              local: participant == room.localParticipant,
              video:
                  participant.videoTrackPublications
                          .where((p) => p.track is VideoTrack && !p.muted)
                          .firstOrNull
                          ?.track
                      is VideoTrack
                  ? VideoTrackRenderer(
                      participant.videoTrackPublications
                              .where((p) => p.track is VideoTrack && !p.muted)
                              .first
                              .track
                          as VideoTrack,
                      key: ValueKey(participant.identity),
                      fit: VideoViewFit.cover,
                    )
                  : null,
            ),
        ],
        onClose: close,
        controls: [
          CallControl(
            label: 'Микрофон',
            tooltip: microphone ? 'Выключить микрофон' : 'Включить микрофон',
            icon: microphone ? Icons.mic_rounded : Icons.mic_off_rounded,
            selected: !microphone,
            onPressed: enabled
                ? () => control(() async {
                    final next = !microphone;
                    await room.localParticipant?.setMicrophoneEnabled(next);
                    microphone = next;
                  })
                : null,
          ),
          CallControl(
            label: 'Камера',
            tooltip: camera ? 'Выключить камеру' : 'Включить камеру',
            icon: camera ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            selected: camera,
            onPressed: enabled
                ? () => control(() async {
                    if (!camera && !await callPermission(Permission.camera)) {
                      throw ApiFailure(
                        403,
                        'Разрешите камеру в настройках MyKIDS на разблокированном телефоне',
                      );
                    }
                    ensureOpen();
                    final next = !camera;
                    if (next) {
                      await startNativeService(true);
                      ensureOpen();
                    }
                    await room.localParticipant?.setCameraEnabled(next);
                    ensureOpen();
                    camera = next;
                    if (next) cameraUnavailable = false;
                    if (!next) {
                      await startNativeService(false);
                    }
                  })
                : null,
          ),
          CallControl(
            label: 'Динамик',
            icon: speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
            selected: speaker,
            onPressed: enabled
                ? () => control(() async {
                    final next = !speaker;
                    await routeSpeaker(next, force: next);
                    speaker = next;
                  })
                : null,
          ),
          CallControl(
            label: 'Сменить камеру',
            icon: Icons.cameraswitch_rounded,
            onPressed: enabled && camera
                ? () => control(() async {
                    final next = !front;
                    for (final p
                        in room.localParticipant?.videoTrackPublications ??
                            <LocalTrackPublication>[]) {
                      if (p.track is LocalVideoTrack) {
                        await (p.track as LocalVideoTrack).setCameraPosition(
                          next ? CameraPosition.front : CameraPosition.back,
                        );
                      }
                    }
                    front = next;
                  })
                : null,
          ),
          CallControl(
            label: 'Bluetooth',
            icon: Icons.bluetooth_rounded,
            onPressed: enabled
                ? () => control(() async {
                    await Permission.bluetoothConnect.request();
                    await routeSpeaker(false);
                    speaker = false;
                  })
                : null,
          ),
          CallControl(
            label: 'Пригласить',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: enabled && reservedPeople.length < 4
                ? inviteParticipant
                : null,
          ),
        ],
      ),
    );
  }
}
