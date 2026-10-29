import 'dart:async';

import 'design_system.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';

import 'incoming_calls.dart';
import 'family_contacts.dart';
import 'family_action.dart';
import 'messenger_widgets.dart';
import 'repository.dart';
import 'schedule.dart';
import 'task_photo_viewer.dart';
import 'visuals.dart';
import 'voice_note.dart';
import 'engagement/engagement_entries.dart';
import 'engagement/engagement_scope.dart';

String _conversationTitle(Map<String, dynamic> room) =>
    gameDesign.value != null &&
        room['kind'] == 'family' &&
        room['title'] == 'Вся семья'
    ? 'Наша семья'
    : conversationName(room);

bool _showChat(Map<String, dynamic> room) =>
    gameDesign.value == null ||
    room['kind'] == 'family' ||
    !room.containsKey('last_message') ||
    room['last_message'] != null ||
    (room['unread_count'] as num? ?? 0) > 0;

class FamilyScreen extends StatelessWidget {
  final FamilyRepository repository;
  final Future<void> Function(Future<Map<String, dynamic>> Function()) perform;
  const FamilyScreen({
    super.key,
    required this.repository,
    required this.perform,
  });
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final allRooms = repository.rows('rooms');
        // Empty private rooms support contacts and calls. Keep them available
        // there while the chat list shows conversations with known history.
        // Older cached snapshots without summaries must remain accessible.
        final orderedRooms = [...allRooms]
          ..sort(
            (a, b) => a['kind'] == 'family'
                ? (b['kind'] == 'family' ? 0 : -1)
                : b['kind'] == 'family'
                ? 1
                : ((b['last_message'] as Map?)?['created_at'] as String? ?? '')
                      .compareTo(
                        (a['last_message'] as Map?)?['created_at'] as String? ??
                            '',
                      ),
          );
        final calls = repository.rows('calls');
        return Material(
          color: gameDesign.value?.surface ?? Colors.white,
          child: Column(
            children: [
              if (gameDesign.value != null)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: GameScene(
                    title: 'Семья рядом',
                    description: 'Близкие всегда на связи',
                    compact: true,
                  ),
                ),
              if (gameDesign.value == null)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Семья рядом',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (EngagementScope.maybeOf(context) != null)
                const FamilyMissionEntry(compact: true),
              TabBar(
                isScrollable: MediaQuery.textScalerOf(context).scale(14) > 20,
                labelColor: Theme.of(context).colorScheme.primary,
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: const [
                  Tab(text: 'Чаты'),
                  Tab(text: 'Контакты'),
                  Tab(text: 'Звонки'),
                ],
              ),
              if (!repository.online)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Нет связи · показаны сохранённые данные',
                    style: TextStyle(color: messengerMuted),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    FutureBuilder<List<Map<String, Object?>>>(
                      key: ValueKey((
                        repository.sessionTag,
                        repository.generation,
                      )),
                      future: gameDesign.value == null
                          ? Future.value(const <Map<String, Object?>>[])
                          : repository.pending(),
                      builder: (context, pending) {
                        final queuedRooms = <String, bool>{};
                        for (final row
                            in pending.data ?? const <Map<String, Object?>>[]) {
                          final match = RegExp(r'^/v1/rooms/([^/]+)/messages$')
                              .firstMatch(row['path'] as String? ?? '');
                          if (match != null && row['method'] == 'POST') {
                            final id = match[1]!;
                            queuedRooms[id] =
                                queuedRooms[id] == true ||
                                row['state'] == 'failed';
                          }
                        }
                        // A stale offline summary cannot prove a conversation
                        // is empty. Queued first messages must remain reachable.
                        final rooms = orderedRooms
                            .where(
                              (room) =>
                                  !repository.online ||
                                  pending.hasError ||
                                  queuedRooms.containsKey(room['id']) ||
                                  _showChat(room),
                            )
                            .toList();
                        return rooms.isEmpty
                            ? const _EmptyConversations(
                                icon: Icons.chat_bubble_outline,
                                text: 'Здесь появятся семейные чаты',
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: rooms.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  indent: 84,
                                  color: chatBackground,
                                ),
                                itemBuilder: (context, index) {
                                  final room = rooms[index];
                                  final last = room['last_message'] as Map?;
                                  final count =
                                      room['unread_count'] as int? ?? 0;
                                  final title = _conversationTitle(room);
                                  final sender =
                                      repository
                                              .rows('members')
                                              .where(
                                                (m) =>
                                                    m['id'] ==
                                                    last?['sender_id'],
                                              )
                                              .firstOrNull?['name']
                                          as String?;
                                  final content =
                                      last?['text'] as String? ?? '';
                                  final preview =
                                      queuedRooms.containsKey(room['id'])
                                      ? queuedRooms[room['id']] == true
                                            ? 'Не отправлено'
                                            : 'Ждёт отправки'
                                      : last == null
                                      ? gameDesign.value != null &&
                                                !repository.online
                                            ? 'Нужен интернет'
                                            : (room.containsKey('last_message')
                                                  ? 'Начните разговор'
                                                  : 'Откройте переписку')
                                      : '${last['sender_id'] == repository.userId
                                            ? 'Вы: '
                                            : sender != null
                                            ? '$sender: '
                                            : ''}${content.isNotEmpty
                                            ? content
                                            : (last['attachment_mime'] as String? ?? '').startsWith('audio/')
                                            ? 'Голосовое сообщение'
                                            : 'Фото'}';
                                  return ListTile(
                                    tileColor: Colors.white,
                                    leading: FamilyAvatar(
                                      name: title,
                                      group: room['kind'] == 'family',
                                    ),
                                    title: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      preview,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: messengerMuted,
                                        fontWeight: count > 0
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    trailing: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          messageTime(last?['created_at']),
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1,
                                            color: count > 0
                                                ? actionBlue
                                                : messengerMuted,
                                          ),
                                        ),
                                        if (count > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Semantics(
                                              label:
                                                  'Непрочитанных сообщений: $count',
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: actionBlue,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  count > 99 ? '99+' : '$count',
                                                  textScaler:
                                                      TextScaler.noScaling,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => ChatScreen(
                                            repository: repository,
                                            room: room,
                                          ),
                                        ),
                                      );
                                      if (repository.signedIn) {
                                        await repository.sync();
                                      }
                                    },
                                  );
                                },
                              );
                      },
                    ),
                    _FamilyContacts(repository: repository),
                    calls.isEmpty
                        ? const _EmptyConversations(
                            icon: Icons.call_outlined,
                            text: 'Звонков пока нет. Позвоните из чата.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: calls.length,
                            itemBuilder: (context, index) {
                              final call = calls[index];
                              final callRoom = allRooms
                                  .where((r) => r['id'] == call['room_id'])
                                  .firstOrNull;
                              final title = callRoom == null
                                  ? (repository
                                                .rows('members')
                                                .where(
                                                  (m) =>
                                                      m['id'] ==
                                                      call['caller_id'],
                                                )
                                                .firstOrNull?['name']
                                            as String? ??
                                        'Семейный звонок')
                                  : _conversationTitle(callRoom);
                              final incoming =
                                  call['caller_id'] != repository.userId;
                              final active =
                                  callRoom?['kind'] != 'family' &&
                                  [
                                    'ringing',
                                    'active',
                                  ].contains(call['status']) &&
                                  [
                                    'invited',
                                    'joined',
                                  ].contains(call['member_status']);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    tileColor: Colors.white,
                                    leading: FamilyAvatar(
                                      name: title,
                                      group: callRoom?['kind'] == 'family',
                                    ),
                                    title: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${incoming ? 'Входящий' : 'Исходящий'} · ${statusText(call['status'] as String)}\n${messageDay(call['created_at'])} ${messageTime(call['created_at'])}',
                                      style: const TextStyle(
                                        color: messengerMuted,
                                      ),
                                    ),
                                    trailing: Icon(
                                      call['video'] == 1
                                          ? Icons.videocam_outlined
                                          : Icons.call_outlined,
                                      color: actionBlue,
                                    ),
                                  ),
                                  if (active)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 76,
                                        right: 12,
                                        bottom: 8,
                                      ),
                                      child: Wrap(
                                        spacing: 8,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () => openFamilyCall(
                                              context,
                                              repository,
                                              call['id'] as String,
                                            ),
                                            icon: const Icon(Icons.call),
                                            label: Text(
                                              call['member_status'] == 'joined'
                                                  ? 'Вернуться'
                                                  : 'Ответить',
                                            ),
                                          ),
                                          if (call['member_status'] ==
                                              'invited')
                                            TextButton(
                                              onPressed: () => perform(
                                                () => repository.mutate(
                                                  '/v1/calls/${call['id']}/actions',
                                                  {'action': 'decline'},
                                                ),
                                              ),
                                              child: const Text('Отклонить'),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _FamilyContacts extends StatefulWidget {
  final FamilyRepository repository;
  const _FamilyContacts({required this.repository});
  @override
  State<_FamilyContacts> createState() => _FamilyContactsState();
}

class _FamilyContactsState extends State<_FamilyContacts> {
  String query = '';
  bool opening = false;
  Future<void> openContact(String id) async {
    if (opening) return;
    setState(() => opening = true);
    final identity = widget.repository.sessionTag;
    try {
      var room = contactRoom(widget.repository, id);
      if (room == null) {
        await widget.repository.sync();
        room = contactRoom(widget.repository, id);
      }
      if (!mounted ||
          widget.repository.sessionTag != identity ||
          !widget.repository.signedIn) {
        return;
      }
      if (room == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Переписка пока недоступна. Попробуйте позже.'),
          ),
        );
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                ChatScreen(repository: widget.repository, room: room!),
          ),
        );
      }
    } catch (_) {
      if (mounted &&
          widget.repository.sessionTag == identity &&
          widget.repository.signedIn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть переписку. Попробуйте ещё раз.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = familyContacts(widget.repository)
        .where(
          (member) => (member['name'] as String).toLowerCase().contains(
            query.trim().toLowerCase(),
          ),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const ValueKey('contact-search'),
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              hintText: 'Поиск контакта',
              prefixIcon: Icon(Icons.search),
              filled: true,
              fillColor: chatBackground,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
            ),
          ),
        ),
        Expanded(
          child: contacts.isEmpty
              ? const _EmptyConversations(
                  icon: Icons.people_outline,
                  text: 'Контакты не найдены',
                )
              : ListView.separated(
                  itemCount: contacts.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    indent: 84,
                    color: chatBackground,
                  ),
                  itemBuilder: (context, index) {
                    final member = contacts[index];
                    return ListTile(
                      key: ValueKey('contact-${member['id']}'),
                      leading: FamilyAvatar(name: member['name'] as String),
                      title: Text(
                        member['name'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        const {
                              'child': 'Ребёнок',
                              'parent': 'Родитель',
                              'relative': 'Родственник',
                            }[member['role']] ??
                            'Семья',
                        style: const TextStyle(color: messengerMuted),
                      ),
                      trailing: const Icon(
                        Icons.chat_bubble_outline,
                        color: actionBlue,
                      ),
                      onTap: opening
                          ? null
                          : () => openContact(member['id'] as String),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyConversations extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyConversations({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: actionBlue),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: messengerMuted),
          ),
        ],
      ),
    ),
  );
}

class _ChatLeaveDecision extends StatelessWidget {
  final FamilyActionAccess access;
  const _ChatLeaveDecision({required this.access});

  @override
  Widget build(BuildContext context) => FamilyActionDialog<bool>(
    // This decision only removes an owned local draft and must work offline.
    // Validate the captured reader below; the wrapper guards route and reuse.
    builder: (context, close) => AnimatedBuilder(
      animation: Listenable.merge([access, access.repository]),
      builder: (_, _) {
        if (!access.valid) {
          return AlertDialog(
            scrollable: true,
            title: const Text('Нужно открыть окно заново'),
            content: const Text(
              'Семейный доступ изменился. Закройте это окно.',
            ),
            actions: [
              TextButton(
                onPressed: () => close(null),
                child: const Text('Закрыть'),
              ),
            ],
          );
        }
        return AlertDialog(
          scrollable: true,
          title: const Text('Удалить голосовую запись?'),
          content: const Text('Запись ещё не отправлена.'),
          actions: [
            TextButton(
              onPressed: () {
                if (access.valid) close(false);
              },
              child: const Text('Остаться'),
            ),
            TextButton(
              onPressed: () {
                if (access.valid) close(true);
              },
              child: const Text('Удалить и выйти'),
            ),
          ],
        );
      },
    ),
  );
}

class ChatScreen extends StatefulWidget {
  final FamilyRepository repository;
  final Map<String, dynamic> room;
  final AudioPlayer? audioPlayer;
  final VoiceCapture? voiceCapture;
  const ChatScreen({
    super.key,
    required this.repository,
    required this.room,
    this.audioPlayer,
    this.voiceCapture,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final text = TextEditingController();
  late final player = widget.audioPlayer ?? AudioPlayer();
  late final VoiceNote voice;
  Timer? poll;
  int mediaEpoch = 0;
  bool routeVisible = true, leaving = false, closingForAccess = false;
  FamilyActionAccess? leavingAccess;
  Timer? readCheck;
  final messageScroll = ScrollController();
  final messageViewport = GlobalKey();
  final messageKeys = <String, GlobalKey>{};
  final acknowledgedReads = <String>{};
  bool markingRead = false;
  late final FamilyRepository readerRepository;
  late final String? readerToken;
  late final String readerEndpoint, readerUserId, readerRoomId;
  late final int readerGeneration;
  List<Map<String, dynamic>> messages = [];
  bool busy = false;
  bool get recording => voice.recording;
  bool loading = false, loadingEarlier = false, hasEarlier = false;
  int loadRevision = 0;
  bool reloadAfterResume = false;
  String? error;
  String? actionError;
  FamilyRepository get repo => widget.repository;
  bool get foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get sameReader =>
      identical(repo, readerRepository) &&
      repo.signedIn &&
      repo.token == readerToken &&
      repo.endpoint == readerEndpoint &&
      repo.userId == readerUserId &&
      widget.room['id'] == readerRoomId &&
      repo.generation == readerGeneration;
  bool get canReadVisible =>
      mounted &&
      sameReader &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      ModalRoute.of(context)?.isCurrent != false;
  String get roomId => widget.room['id'] as String;
  Map<String, dynamic> get currentRoom =>
      repo.rows('rooms').where((r) => r['id'] == roomId).firstOrNull ??
      widget.room;
  bool get canCall {
    final peer = (currentRoom['contact'] as Map?)?['id'];
    return currentRoom['kind'] == 'private' &&
        currentRoom['can_call'] != false &&
        (peer == null ||
            repo
                .rows('members')
                .any((m) => m['id'] == peer && m['active'] == 1));
  }

  @override
  void initState() {
    super.initState();
    readerRepository = repo;
    readerToken = repo.token;
    readerEndpoint = repo.endpoint;
    readerUserId = repo.userId;
    readerRoomId = roomId;
    readerGeneration = repo.generation;
    voice = VoiceNote(
      capture: widget.voiceCapture,
      isOwner: () => mounted && sameReader,
      isActive: () => canReadVisible,
    )..addListener(voiceChanged);
    WidgetsBinding.instance.addObserver(this);
    messageScroll.addListener(scheduleReadCheck);
    repo.addListener(accessChanged);
    unawaited(load());
    startPoll();
  }

  void startPoll() {
    poll?.cancel();
    if (foreground) {
      poll = Timer.periodic(const Duration(seconds: 5), (_) => load());
    }
  }

  void voiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!sameReader) accessChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (routeVisible && !visible) {
      unawaited(suspendMedia(cancelPermission: true));
    }
    routeVisible = visible;
  }

  Future<void> stopPlayback() async {
    mediaEpoch++;
    await player.stop();
  }

  Future<void> suspendMedia({bool cancelPermission = false}) async {
    try {
      await Future.wait([
        stopPlayback(),
        voice.suspend(cancelPermission: cancelPermission),
      ]);
    } catch (_) {
      if (mounted && sameReader) {
        setState(() => actionError = 'Не удалось завершить запись');
      }
    }
  }

  void accessChanged() {
    final access = leavingAccess;
    if (access != null && !access.valid) access.invalidate();
    if (!sameReader) {
      messages = [];
      text.clear();
      unawaited(
        Future.wait([stopPlayback(), voice.cancel()]).catchError((Object _) {
          debugPrint('MyKIDS: chat media cleanup requires retry');
          return <void>[];
        }),
      );
    }
    if (!repo.signedIn && mounted) {
      final route = ModalRoute.of(context);
      // An incoming call or a photo may be above this chat. Remove only this
      // route, and keep a root chat masked instead of leaving an empty stack.
      if (route != null && !route.isFirst && !closingForAccess) {
        closingForAccess = true;
        final navigator = Navigator.of(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && route.isActive && !sameReader) {
            navigator.removeRoute(route);
          }
        });
      }
    }
    if (mounted) {
      setState(() {});
      if (sameReader) scheduleReadCheck();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    readCheck?.cancel();
    if (state == AppLifecycleState.resumed) {
      voice.resume();
      startPoll();
      reloadAfterResume = true;
      unawaited(load());
      scheduleReadCheck();
    } else {
      loadRevision++;
      poll?.cancel();
      unawaited(
        suspendMedia(cancelPermission: state != AppLifecycleState.inactive),
      );
    }
  }

  @override
  void didChangeMetrics() => scheduleReadCheck();

  void scheduleReadCheck() {
    if (!mounted || !sameReader) return;
    readCheck?.cancel();
    readCheck = Timer(const Duration(milliseconds: 200), markVisibleRead);
  }

  bool messageVisible(String id) {
    final viewport = messageViewport.currentContext?.findRenderObject();
    final bubble = messageKeys[id]?.currentContext?.findRenderObject();
    if (viewport is! RenderBox ||
        bubble is! RenderBox ||
        !viewport.attached ||
        !bubble.attached ||
        !viewport.hasSize ||
        !bubble.hasSize) {
      return false;
    }
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final bounds = (viewport.localToGlobal(Offset.zero) & viewport.size)
        .intersect(screen);
    final message = bubble.localToGlobal(Offset.zero) & bubble.size;
    final visible = message.intersect(bounds);
    final requiredHeight =
        (message.height < bounds.height ? message.height : bounds.height) * .5;
    return requiredHeight > 0 &&
        visible.height >= requiredHeight &&
        visible.width >= message.width * .5;
  }

  Future<void> markVisibleRead() async {
    if (markingRead || !canReadVisible) return;
    final viewed = messages
        .where((message) {
          final id = message['id'] as String;
          return message['sender_id'] != readerUserId &&
              !acknowledgedReads.contains(id) &&
              !(message['receipts'] as List? ?? []).any(
                (r) => r['user_id'] == readerUserId && r['read_at'] != null,
              ) &&
              messageVisible(id);
        })
        .map((message) => message['id'] as String)
        .toList(growable: false);
    markingRead = true;
    var confirmed = false;
    try {
      // These messages were seen together. Finish their receipts even when
      // the reader goes back before the first network response arrives.
      for (final id in viewed) {
        if (!sameReader) break;
        final receipt = await repo.request(
          '/v1/messages/$id/receipt',
          method: 'POST',
          key: 'read:$id:$readerUserId',
          body: {'status': 'read'},
        );
        if (receipt['ok'] != true) {
          throw ApiFailure(502, 'Не удалось подтвердить прочтение');
        }
        if (!sameReader) return;
        acknowledgedReads.add(id);
        confirmed = true;
      }
    } catch (_) {
      // Keep the unread state after a failed receipt. Loading, scrolling or
      // reconnecting will retry while the message is still visible.
    } finally {
      markingRead = false;
      if (confirmed && sameReader) {
        if (mounted) setState(() {});
        await repo.refreshAfterChange();
      }
    }
  }

  @override
  void dispose() {
    leavingAccess?.invalidate();
    readerRepository.removeListener(accessChanged);
    WidgetsBinding.instance.removeObserver(this);
    readCheck?.cancel();
    messageScroll.dispose();
    poll?.cancel();
    voice.removeListener(voiceChanged);
    voice.dispose();
    mediaEpoch++;
    player.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> load({bool earlier = false}) async {
    if (busy || loading || !sameReader || !foreground) return;
    final revision = loadRevision;
    if (!earlier) reloadAfterResume = false;
    loading = true;
    if (earlier && mounted) setState(() => loadingEarlier = true);
    try {
      final result = await repo.request(
        '/v1/rooms/$roomId/messages',
        query: earlier && messages.isNotEmpty
            ? {'before_id': messages.first['id'] as String}
            : null,
      );
      final loaded = (result['messages'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted && sameReader && foreground && revision == loadRevision) {
        setState(() {
          final combined = {
            for (final message in messages) message['id']: message,
            for (final message in loaded) message['id']: message,
          };
          messages = combined.values.toList()
            ..sort((a, b) {
              final byDate = (a['created_at'] as String).compareTo(
                b['created_at'] as String,
              );
              return byDate != 0
                  ? byDate
                  : (a['id'] as String).compareTo(b['id'] as String);
            });
          if (earlier || combined.length == loaded.length) {
            hasEarlier = result['has_more'] == true;
          }
          error = null;
        });
      }
      if (!mounted || !sameReader || !foreground || revision != loadRevision) {
        return;
      }
      for (final message in loaded.where(
        (m) =>
            m['sender_id'] != repo.userId &&
            (m['receipts'] as List)
                .where(
                  (r) =>
                      r['user_id'] == repo.userId && r['delivered_at'] != null,
                )
                .isEmpty,
      )) {
        if (!mounted ||
            !sameReader ||
            !foreground ||
            revision != loadRevision) {
          return;
        }
        if (acknowledgedReads.contains(message['id'])) continue;
        await repo.request(
          '/v1/messages/${message['id']}/receipt',
          method: 'POST',
          key: 'delivered:${message['id']}:${repo.userId}',
          body: {'status': 'delivered'},
        );
      }
    } catch (_) {
      if (mounted && sameReader && foreground && revision == loadRevision) {
        setState(() => error = 'Для семейного чата нужен интернет');
      }
    } finally {
      loading = false;
      if (mounted) {
        setState(() => loadingEarlier = false);
        scheduleReadCheck();
        if (reloadAfterResume && sameReader && foreground && !busy) {
          unawaited(load());
        }
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || !canReadVisible) return;
    setState(() {
      busy = true;
      actionError = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && sameReader) {
        setState(
          () => actionError = e is ApiFailure
              ? e.message
              : 'Не удалось выполнить действие',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load();
  }

  Future<void> sendFile(String path) async {
    if (!sameReader) throw ApiFailure(401, 'Семейный доступ изменён');
    final target = readerRoomId;
    final upload = await readerRepository.upload(path, 'room', target);
    if (!sameReader) throw ApiFailure(401, 'Семейный доступ изменён');
    await readerRepository.mutate('/v1/rooms/$target/messages', {
      'attachment_id': upload['id'],
    });
  }

  Future<void> recordVoice() async {
    if (voice.canFinish) return voice.finish();
    FocusManager.instance.primaryFocus?.unfocus();
    await stopPlayback();
    if (canReadVisible) await voice.start();
  }

  Future<void> cancelVoice() async {
    try {
      await Future.wait([voice.cancel(), stopPlayback()]);
      if (mounted && sameReader) setState(() => actionError = null);
    } catch (_) {
      if (mounted && sameReader) {
        setState(() => actionError = 'Не удалось удалить запись');
      }
    }
  }

  Future<void> playVoice(String path, int epoch) async {
    try {
      await player.setFilePath(path);
      if (!canReadVisible || epoch != mediaEpoch || recording) return;
      unawaited(
        player.play().catchError((Object _) {
          if (mounted && sameReader && epoch == mediaEpoch) {
            setState(
              () => actionError = 'Не удалось прослушать голосовое сообщение',
            );
          }
        }),
      );
    } catch (_) {
      if (epoch == mediaEpoch && canReadVisible) rethrow;
    }
  }

  Future<void> previewVoice() => run(() async {
    final path = voice.draft;
    if (path == null) return;
    await stopPlayback();
    if (canReadVisible) await playVoice(path, mediaEpoch);
  });

  Future<void> sendVoice() => run(() async {
    await stopPlayback();
    if (canReadVisible) await voice.send(sendFile);
  });

  Widget voicePanel() => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(28),
    child: Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        children: [
          Icon(
            recording ? Icons.mic : Icons.graphic_eq,
            color: recording ? Colors.red : messengerMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(switch (voice.phase) {
              VoiceNotePhase.permission => 'Разрешение микрофона…',
              VoiceNotePhase.starting => 'Подготовка записи…',
              VoiceNotePhase.recording => 'Идёт запись…',
              VoiceNotePhase.stopping => 'Завершаем запись…',
              VoiceNotePhase.sending => 'Отправляем запись…',
              _ => 'Запись готова',
            }, style: const TextStyle(color: messengerMuted)),
          ),
          if (voice.phase == VoiceNotePhase.ready)
            IconButton(
              tooltip: 'Прослушать запись',
              onPressed: busy ? null : previewVoice,
              icon: const Icon(Icons.play_circle_outline),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          IconButton(
            tooltip: 'Отменить запись',
            onPressed: voice.phase == VoiceNotePhase.sending
                ? null
                : cancelVoice,
            icon: const Icon(Icons.close),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          IconButton.filled(
            tooltip: recording ? 'Остановить запись' : 'Отправить запись',
            onPressed: busy
                ? null
                : recording
                ? () => run(recordVoice)
                : voice.canSend
                ? sendVoice
                : null,
            style: IconButton.styleFrom(
              backgroundColor: actionBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size(52, 52),
            ),
            icon: Icon(recording ? Icons.stop_rounded : Icons.send_rounded),
          ),
        ],
      ),
    ),
  );

  Future<void> leaveChat() async {
    if (leaving || !canReadVisible) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    final access = FamilyActionAccess(
      readerRepository,
      permitted: () => mounted && sameReader,
    );
    if (!access.valid) {
      access.dispose();
      return;
    }
    leaving = true;
    leavingAccess = access;
    try {
      await suspendMedia();
      if (!mounted || !canReadVisible || !access.valid || !route.isCurrent) {
        return;
      }
      final discard =
          !voice.hasUnsent ||
          await showFamilyActionDialog<bool>(
                context: context,
                builder: (_) => _ChatLeaveDecision(access: access),
              ) ==
              true;
      if (!discard || !canReadVisible || !access.valid || !route.isCurrent) {
        return;
      }
      await voice.cancel();
      if (canReadVisible &&
          access.valid &&
          route.isCurrent &&
          navigator.canPop()) {
        navigator.pop();
      }
    } finally {
      leavingAccess = null;
      access.dispose();
      leaving = false;
    }
  }

  Future<void> startCall(bool video) => run(() async {
    final call = await repo.mutate('/v1/rooms/$roomId/calls', {'video': video});
    if (mounted && call['id'] != null && canReadVisible) {
      await openFamilyCall(context, repo, call['id'] as String);
    }
  });

  Future<void> sendText() => run(() async {
    final value = text.text;
    if (value.trim().isEmpty) return;
    await repo.mutate('/v1/rooms/$roomId/messages', {'text': value});
    // Do not erase a draft edited while the request was pending.
    if (mounted && text.text == value) text.clear();
  });

  Future<void> openAttachment(Map<String, dynamic> message) => run(() async {
    await stopPlayback();
    final epoch = mediaEpoch;
    if (!canReadVisible) return;
    final file = await repo.attachment(message['attachment_id'] as String);
    if (!canReadVisible || epoch != mediaEpoch) return;
    final bytes = await file
        .openRead(0, 12)
        .fold<List<int>>([], (a, b) => a..addAll(b));
    if (!mounted || !canReadVisible || epoch != mediaEpoch) return;
    if (String.fromCharCodes(bytes.take(4)) == 'RIFF') {
      await playVoice(file.path, epoch);
    } else {
      // Capture the reader before push: navigation observers can change the
      // account before the route builder first runs.
      final viewer = TaskPhotoViewer(
        repository: readerRepository,
        photos: [() async => file],
      );
      final route = MaterialPageRoute<void>(builder: (_) => viewer);
      await Navigator.of(context).push(route);
      await route.completed;
    }
  });

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => scheduleReadCheck());
    return PopScope<void>(
      canPop: !voice.hasUnsent,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(leaveChat());
      },
      child: buildChat(context),
    );
  }

  Widget buildChat(BuildContext context) {
    if (!sameReader) {
      return Scaffold(
        appBar: AppBar(title: const Text('Чат недоступен')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Доступ изменён. Откройте чат заново.'),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: gameDesign.value?.background ?? chatBackground,
      appBar: AppBar(
        backgroundColor: gameDesign.value?.surface ?? Colors.white,
        foregroundColor: ink,
        titleSpacing: 0,
        title: Row(
          children: [
            FamilyAvatar(
              name: _conversationTitle(currentRoom),
              group: widget.room['kind'] == 'family',
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _conversationTitle(currentRoom),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (canCall) ...[
            IconButton(
              tooltip: 'Аудиозвонок',
              onPressed: busy || voice.hasPanel || !sameReader
                  ? null
                  : () => startCall(false),
              icon: const Icon(Icons.call_outlined),
              color: actionBlue,
            ),
            IconButton(
              tooltip: 'Видеозвонок',
              onPressed: busy || voice.hasPanel || !sameReader
                  ? null
                  : () => startCall(true),
              icon: const Icon(Icons.videocam_outlined),
              color: actionBlue,
            ),
          ],
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, bounds) {
            final compact = bounds.maxHeight < 480;
            return Column(
              children: [
                if (actionError != null || voice.error != null || error != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (bounds.maxHeight * .25)
                          .clamp(56.0, 112.0)
                          .toDouble(),
                    ),
                    child: SingleChildScrollView(
                      child: Material(
                        color: warmYellow,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  actionError ?? voice.error ?? error!,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: messages.isEmpty
                      ? Center(
                          child: loading
                              ? const CircularProgressIndicator()
                              : const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Напишите близким или отправьте голосовое сообщение',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: messengerMuted),
                                  ),
                                ),
                        )
                      : ListView.builder(
                          key: messageViewport,
                          controller: messageScroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: messages.length + (hasEarlier ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == messages.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: loading || busy
                                      ? null
                                      : () => load(earlier: true),
                                  child: Text(
                                    loadingEarlier
                                        ? 'Загружаем историю…'
                                        : 'Более ранние сообщения',
                                  ),
                                ),
                              );
                            }
                            final i = messages.length - 1 - index;
                            final message = messages[i];
                            final own = message['sender_id'] == repo.userId;
                            final receipts =
                                (message['receipts'] as List? ?? []).where(
                                  (r) => r['user_id'] != message['sender_id'],
                                );
                            final read = receipts.any(
                              (r) => r['read_at'] != null,
                            );
                            final delivered = receipts.any(
                              (r) => r['delivered_at'] != null,
                            );
                            final readByMe =
                                acknowledgedReads.contains(message['id']) ||
                                receipts.any(
                                  (r) =>
                                      r['user_id'] == repo.userId &&
                                      r['read_at'] != null,
                                );
                            final day = messageDay(message['created_at']);
                            return Column(
                              children: [
                                if (day.isNotEmpty &&
                                    (i == 0 ||
                                        messageDay(
                                              messages[i - 1]['created_at'],
                                            ) !=
                                            day))
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: .85,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5,
                                        ),
                                        child: Text(
                                          day,
                                          style: const TextStyle(
                                            color: messengerMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                KeyedSubtree(
                                  key: messageKeys.putIfAbsent(
                                    message['id'] as String,
                                    GlobalKey.new,
                                  ),
                                  child: MessageBubble(
                                    key: ValueKey(message['id']),
                                    own: own,
                                    sender:
                                        repo
                                                .rows('members')
                                                .where(
                                                  (m) =>
                                                      m['id'] ==
                                                      message['sender_id'],
                                                )
                                                .firstOrNull?['name']
                                            as String? ??
                                        'Семья',
                                    text: message['text'] as String? ?? '',
                                    timestamp: message['created_at'] as String,
                                    read: read,
                                    delivered: delivered,
                                    attachmentLabel:
                                        message['attachment_id'] == null
                                        ? null
                                        : (message['attachment_mime']
                                                      as String? ??
                                                  '')
                                              .startsWith('audio/')
                                        ? 'Голосовое сообщение'
                                        : message['attachment_mime'] != null
                                        ? 'Открыть фото'
                                        : 'Фото или голосовое',
                                    onAttachment: busy || recording
                                        ? null
                                        : () => openAttachment(message),
                                    onRead: own || readByMe || busy
                                        ? null
                                        : () => run(() async {
                                            await repo.mutate(
                                              '/v1/messages/${message['id']}/receipt',
                                              {'status': 'read'},
                                            );
                                          }),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (context, state) =>
                      state.data?.playing == true &&
                          state.data?.processingState !=
                              ProcessingState.completed
                      ? Material(
                          color: Colors.white,
                          child: ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.graphic_eq,
                              color: actionBlue,
                            ),
                            title: const Text('Голосовое сообщение'),
                            trailing: IconButton(
                              tooltip: 'Остановить звук',
                              onPressed: () => run(stopPlayback),
                              icon: const Icon(Icons.stop_circle_outlined),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: voice.hasPanel
                      ? voicePanel()
                      : ValueListenableBuilder<TextEditingValue>(
                          valueListenable: text,
                          builder: (context, value, _) {
                            final hasText = value.text.trim().isNotEmpty;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: text,
                                    maxLength: 4000,
                                    minLines: 1,
                                    maxLines: bounds.maxHeight < 360
                                        ? 1
                                        : compact
                                        ? 2
                                        : 4,
                                    keyboardType: TextInputType.multiline,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      hintText: 'Сообщение',
                                      counterText: value.text.length > 3800
                                          ? '${value.text.length}/4000'
                                          : '',
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(28),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(28),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(28),
                                        borderSide: const BorderSide(
                                          color: actionBlue,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 12,
                                          ),
                                      suffixIcon: IconButton(
                                        tooltip: 'Фото',
                                        onPressed: busy
                                            ? null
                                            : () => run(() async {
                                                final photo =
                                                    await ImagePicker()
                                                        .pickImage(
                                                          source: ImageSource
                                                              .gallery,
                                                          maxWidth: 2048,
                                                          imageQuality: 88,
                                                        );
                                                if (photo != null &&
                                                    mounted &&
                                                    sameReader) {
                                                  await sendFile(photo.path);
                                                }
                                              }),
                                        icon: const Icon(
                                          Icons.image_outlined,
                                          color: messengerMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton.filled(
                                  tooltip: hasText ? 'Отправить' : 'Голосовое',
                                  onPressed: busy
                                      ? null
                                      : hasText
                                      ? sendText
                                      : () => run(recordVoice),
                                  style: IconButton.styleFrom(
                                    backgroundColor: actionBlue,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(52, 52),
                                  ),
                                  icon: busy
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          hasText
                                              ? Icons.send_rounded
                                              : Icons.mic_rounded,
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
