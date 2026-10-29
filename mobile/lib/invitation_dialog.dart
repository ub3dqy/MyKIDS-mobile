import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'invitation.dart';
import 'repository.dart';
import 'background.dart' show nativeCalls;
import 'form_layout.dart';
import 'family_action.dart';

/// Capture before requesting a secret, never when a late response is rendered.
class InvitationOwner extends ChangeNotifier {
  final FamilyRepository repository;
  late final FamilyActionAccess _access;
  late bool _current;
  InvitationOwner(this.repository) {
    _access = FamilyActionAccess(
      repository,
      permitted: () => repository.role == 'parent',
    );
    _current = _access.valid;
    repository.addListener(changed);
    _access.addListener(changed);
  }

  bool get current => _current && _access.valid;

  void changed() {
    // Observe revocation while a request is pending, before the dialog exists.
    _current = _access.valid;
    notifyListeners();
  }

  void invalidate() => _access.invalidate();

  @override
  void dispose() {
    repository.removeListener(changed);
    _access.removeListener(changed);
    _access.dispose();
    super.dispose();
  }
}

class FamilyInvitations extends StatefulWidget {
  final FamilyRepository repository;
  final Future<void> Function(Future<Map<String, dynamic>> Function()) perform;
  const FamilyInvitations({
    super.key,
    required this.repository,
    required this.perform,
  });
  @override
  State<FamilyInvitations> createState() => _FamilyInvitationsState();
}

class _FamilyInvitationsState extends State<FamilyInvitations> {
  bool creating = false;
  InvitationOwner? creatingOwner;

  @override
  void didUpdateWidget(covariant FamilyInvitations oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      creatingOwner?.invalidate();
    }
  }

  @override
  void dispose() {
    creatingOwner?.invalidate();
    super.dispose();
  }

  Future<void> create(String role) async {
    if (creating || !mounted || !widget.repository.online) return;
    final owner = InvitationOwner(widget.repository);
    final route = ModalRoute.of(context);
    bool current() =>
        mounted &&
        identical(widget.repository, owner.repository) &&
        owner.current &&
        (route == null || route.isCurrent);
    if (!current()) {
      owner.dispose();
      return;
    }
    final started = DateTime.now().toUtc();
    setState(() => creating = true);
    creatingOwner = owner;
    try {
      await widget.perform(() async {
        if (!mounted || !current()) {
          throw ApiFailure(
            409,
            'Семейный доступ изменился. Создайте приглашение заново.',
          );
        }
        final result = await owner.repository.request(
          '/v1/invites',
          method: 'POST',
          body: {'role': role},
        );
        if (!mounted || !current()) {
          throw ApiFailure(
            409,
            'Семейный доступ изменился. Создайте приглашение заново.',
          );
        }
        final seconds = result['expires_in'];
        final token = result['token'];
        if (seconds is! int ||
            seconds <= 0 ||
            seconds > 86400 ||
            token is! String) {
          throw ApiFailure(
            502,
            'Сервер вернул неполное приглашение. Попробуйте ещё раз.',
          );
        }
        final expiresAt = started.add(Duration(seconds: seconds));
        if (!DateTime.now().toUtc().isBefore(expiresAt)) {
          throw ApiFailure(409, 'Срок приглашения истёк. Создайте новое.');
        }
        final invitation = Invitation(role: role, token: token);
        await showFamilyActionDialog<void>(
          context: context,
          builder: (_) => InvitationDialog(
            invitation: invitation,
            owner: owner,
            expiresAt: expiresAt,
          ),
        );
        if (!owner.current) throw ApiFailure(409, 'Семейный доступ изменился.');
        return {'message': 'Окно приглашения закрыто'};
      });
    } finally {
      creatingOwner = null;
      owner.dispose();
      if (mounted) setState(() => creating = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: spacedFormItems([
        for (final role in const {
          'parent': 'Второго родителя',
          'child': 'Ребёнка',
          'relative': 'Бабушку или дедушку',
        }.entries)
          OutlinedButton(
            onPressed:
                creating ||
                    !widget.repository.online ||
                    !widget.repository.signedIn ||
                    widget.repository.role != 'parent'
                ? null
                : () => create(role.key),
            child: Text('Подключить ${role.value.toLowerCase()}'),
          ),
        if (!widget.repository.online)
          const Text(
            'Для нового приглашения нужен интернет. Уже полученный действующий код можно передать без связи.',
          ),
      ]),
    ),
  );
}

class InvitationQr extends StatelessWidget {
  final Invitation invitation;
  const InvitationQr({super.key, required this.invitation});

  @override
  Widget build(BuildContext context) {
    final code = QrCode.fromData(
      data: invitation.qrData,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(320.0, constraints.maxWidth);
        // Four white modules around the code keep it readable by scanners.
        final quietZone = size * 4 / (code.moduleCount + 8);
        return RepaintBoundary(
          key: const ValueKey('invitation-qr'),
          child: QrImageView.withQr(
            qr: code,
            size: size,
            padding: EdgeInsets.all(quietZone),
            backgroundColor: Colors.white,
            gapless: false,
            semanticsLabel: 'QR-код семейного приглашения',
          ),
        );
      },
    );
  }
}

class InvitationDialog extends StatefulWidget {
  final Invitation invitation;
  final InvitationOwner owner;
  final DateTime expiresAt;
  const InvitationDialog({
    super.key,
    required this.invitation,
    required this.owner,
    required this.expiresAt,
  });
  @override
  State<InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<InvitationDialog>
    with WidgetsBindingObserver {
  bool copied = false,
      copying = false,
      closing = false,
      invalidated = false,
      expired = false;
  String? copyError;
  Timer? expiry;
  bool get foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get active =>
      mounted &&
      !invalidated &&
      widget.owner.current &&
      ModalRoute.of(context)?.isCurrent == true &&
      foreground &&
      !expired &&
      DateTime.now().toUtc().isBefore(widget.expiresAt);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.owner.addListener(changed);
    final remaining = widget.expiresAt.difference(DateTime.now().toUtc());
    expired = remaining <= Duration.zero;
    if (!expired) {
      expiry = Timer(remaining, () {
        if (mounted) {
          setState(() {
            expired = true;
            copied = false;
          });
        }
      });
    }
  }

  void changed() {
    if (!mounted) return;
    setState(() {
      if (!widget.owner.current) invalidated = true;
      if (!active) copied = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => changed();

  @override
  void didUpdateWidget(covariant InvitationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.owner, widget.owner) ||
        !identical(oldWidget.invitation, widget.invitation) ||
        oldWidget.expiresAt != widget.expiresAt) {
      oldWidget.owner.removeListener(changed);
      widget.owner.addListener(changed);
      expiry?.cancel();
      invalidated = true;
      copied = false;
    }
  }

  @override
  void dispose() {
    expiry?.cancel();
    widget.owner.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> copy() async {
    if (!active || copying || closing) return;
    setState(() {
      copying = true;
      copyError = null;
    });
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await nativeCalls.invokeMethod('copyInvitation', {
          'token': widget.invitation.token,
        });
      } else {
        await Clipboard.setData(ClipboardData(text: widget.invitation.token));
      }
      if (active) setState(() => copied = true);
    } catch (_) {
      if (active) {
        setState(
          () => copyError = 'Не удалось скопировать код. Попробуйте ещё раз или раскройте «Показать код».',
        );
      }
    } finally {
      if (mounted) setState(() => copying = false);
    }
  }

  void close() {
    if (closing || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() => closing = true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(active ? 'Семейное приглашение' : 'Приглашение недоступно'),
    content: SizedBox(
      width: 320,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: !active
              ? [
                  Text(
                    invalidated || !widget.owner.current
                        ? 'Семейный доступ изменился. Закройте это окно.'
                        : expired ||
                              !DateTime.now().toUtc().isBefore(widget.expiresAt)
                        ? 'Срок приглашения истёк. Создайте новое.'
                        : 'Приглашение скрыто. Вернитесь в приложение, чтобы показать код.',
                  ),
                ]
              : [
                  Text(
                    const {
                      'parent': 'Для второго родителя',
                      'child': 'Для ребёнка',
                      'relative': 'Для бабушки или дедушки',
                    }[widget.invitation.role]!,
                  ),
                  const SizedBox(height: 12),
                  InvitationQr(invitation: widget.invitation),
                  const SizedBox(height: 16),
                  const Text(
                    'На другом телефоне откройте MyKIDS → «У меня есть приглашение» → «Сканировать QR-код».',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Приглашение одноразовое. Показывайте его только члену семьи.',
                  ),
                  const Text('Срок действия — не более 24 часов с создания.'),
                  ExpansionTile(
                    title: const Text('Показать код'),
                    // Only the explicit copy action writes this credential. A normal
                    // selection toolbar would bypass Android's sensitive-copy flag.
                    children: [Text(widget.invitation.token)],
                  ),
                  if (copyError != null)
                    Semantics(liveRegion: true, child: Text(copyError!)),
                ],
        ),
      ),
    ),
    actions: [
      if (active)
        TextButton(
          onPressed: copying || closing ? null : copy,
          child: Text(copied ? 'Код скопирован' : 'Скопировать'),
        ),
      TextButton(
        onPressed: closing ? null : close,
        child: const Text('Закрыть'),
      ),
    ],
  );
}
