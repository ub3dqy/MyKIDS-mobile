import 'dart:async';

import 'package:flutter/material.dart';

import 'repository.dart';

/// Captured before opening a form or waiting for a decision.
class FamilyActionAccess extends ChangeNotifier {
  final FamilyRepository repository;
  final bool Function()? permitted;
  final (String, String, int, String, String) _owner;
  bool _invalidated = false;
  bool _disposed = false;

  FamilyActionAccess(this.repository, {this.permitted})
    : _owner = (
        repository.endpoint,
        repository.sessionTag,
        repository.generation,
        repository.userId,
        repository.role,
      );

  bool get valid {
    if (_disposed) return false;
    if (!repository.signedIn ||
        repository.snapshot == null ||
        _owner !=
            (
              repository.endpoint,
              repository.sessionTag,
              repository.generation,
              repository.userId,
              repository.role,
            ) ||
        permitted?.call() == false) {
      _invalidated = true;
    }
    return !_invalidated;
  }

  void requireCurrent() {
    if (!valid) {
      throw ApiFailure(
        401,
        'Семейный доступ изменился. Откройте форму заново.',
      );
    }
  }

  void invalidate() {
    if (_disposed) return;
    _invalidated = true;
    // The owner can be replaced while Flutter is rebuilding its route.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

Future<T?> showFamilyActionDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}

/// Keeps a decision tied to its owner and consumes its close callback once.
class FamilyActionDialog<T> extends StatefulWidget {
  final FamilyActionAccess? access;
  final bool allowOffline;
  final Widget Function(BuildContext context, void Function(T?) close) builder;

  const FamilyActionDialog({
    super.key,
    this.access,
    this.allowOffline = false,
    required this.builder,
  });

  @override
  State<FamilyActionDialog<T>> createState() => _FamilyActionDialogState<T>();
}

class _FamilyActionDialogState<T> extends State<FamilyActionDialog<T>> {
  bool closing = false;
  bool unavailable = false;

  @override
  void initState() {
    super.initState();
    widget.access?.repository.addListener(changed);
    widget.access?.addListener(changed);
  }

  void changed() {
    if (widget.access?.valid == false) unavailable = true;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant FamilyActionDialog<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.access, widget.access)) {
      unavailable = true;
      oldWidget.access?.repository.removeListener(changed);
      oldWidget.access?.removeListener(changed);
      widget.access?.repository.addListener(changed);
      widget.access?.addListener(changed);
    }
  }

  @override
  void dispose() {
    widget.access?.repository.removeListener(changed);
    widget.access?.removeListener(changed);
    super.dispose();
  }

  void close(T? value) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        closing ||
        (value != null && unavailable) ||
        (value != null &&
            widget.access != null &&
            (!widget.access!.valid ||
                (!widget.allowOffline && !widget.access!.repository.online)))) {
      return;
    }
    setState(() => closing = true);
    Navigator.pop(context, value);
  }

  Widget content(BuildContext context) {
    final access = widget.access;
    final valid = !unavailable && (access?.valid ?? true);
    final online = access?.repository.online ?? true;
    if (!valid || (!widget.allowOffline && !online)) {
      return AlertDialog(
        scrollable: true,
        title: Text(
          valid ? 'Нет связи с сервером' : 'Нужно открыть окно заново',
        ),
        content: Text(
          valid
              ? 'Подтверждение доступно после подключения. Можно закрыть это окно и вернуться позже.'
              : 'Семейный доступ изменился. Закройте это окно.',
        ),
        actions: [
          TextButton(
            onPressed: closing ? null : () => close(null),
            child: const Text('Закрыть'),
          ),
        ],
      );
    }
    return AbsorbPointer(
      absorbing: closing,
      child: widget.builder(context, close),
    );
  }

  @override
  Widget build(BuildContext context) => content(context);
}
