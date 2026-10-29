import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'family_action.dart';
import 'form_layout.dart';

/// Files remain owned by this form until the repository accepts responsibility.
class TaskSubmissionDraft {
  final note = TextEditingController();
  final photos = <String>[];
  final previews = <String, Uint8List>{};
  bool transferred = false;

  Future<void> remove(String path) async {
    photos.remove(path);
    previews.remove(path);
    try {
      await File(path).delete();
    } on FileSystemException {
      // Signing out may have already removed this session's private folder.
      if (await File(path).exists()) rethrow;
    }
  }

  Future<void> dispose() async {
    note.dispose();
    if (!transferred) {
      for (final path in photos.toList()) {
        await remove(path);
      }
    }
  }
}

Future<bool> showTaskSubmission({
  required BuildContext context,
  required FamilyActionAccess access,
  required TaskSubmissionDraft draft,
  required String title,
  required int existing,
  required int needed,
  required bool supplementing,
  required Future<void> Function(List<Future<File> Function()>, int) showPhotos,
  Future<List<String>> Function(int)? selectPhotos,
}) async {
  final route = DialogRoute<bool>(
    context: context,
    builder: (_) => _TaskSubmissionDialog(
      access: access,
      draft: draft,
      title: title,
      existing: existing,
      needed: needed,
      supplementing: supplementing,
      selectPhotos: selectPhotos,
      showPhotos: showPhotos,
    ),
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;
  return result == true && access.valid;
}

class _TaskSubmissionDialog extends StatefulWidget {
  final FamilyActionAccess access;
  final TaskSubmissionDraft draft;
  final String title;
  final int existing, needed;
  final bool supplementing;
  final Future<List<String>> Function(int)? selectPhotos;
  final Future<void> Function(List<Future<File> Function()>, int) showPhotos;

  const _TaskSubmissionDialog({
    required this.access,
    required this.draft,
    required this.title,
    required this.existing,
    required this.needed,
    required this.supplementing,
    required this.selectPhotos,
    required this.showPhotos,
  });

  @override
  State<_TaskSubmissionDialog> createState() => _TaskSubmissionDialogState();
}

class _TaskSubmissionDialogState extends State<_TaskSubmissionDialog> {
  bool selecting = false, closing = false;
  String? photoError;
  TaskSubmissionDraft get draft => widget.draft;
  bool get available => mounted && !closing && widget.access.valid;
  bool get current => available && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    widget.access.repository.addListener(changed);
    widget.access.addListener(changed);
  }

  void changed() {
    // Observe a transient access loss even if it is restored before a frame.
    widget.access.valid;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.access.repository.removeListener(changed);
    widget.access.removeListener(changed);
    super.dispose();
  }

  Future<void> pickPhotos() async {
    if (!current || selecting || widget.existing + draft.photos.length >= 5) {
      return;
    }
    setState(() {
      selecting = true;
      photoError = null;
    });
    try {
      final limit = 5 - widget.existing - draft.photos.length;
      final selected = widget.selectPhotos != null
          ? await widget.selectPhotos!(limit)
          : (await ImagePicker().pickMultiImage(
              maxWidth: 2048,
              maxHeight: 2048,
              imageQuality: 88,
              limit: limit,
            )).map((image) => image.path).toList();
      for (final source in selected.take(limit)) {
        if (!current) break;
        String? copy;
        var retained = false;
        try {
          copy = await widget.access.repository.keepFile(source);
          if (!current) continue;
          final preview = await File(copy).readAsBytes();
          if (!current) continue;
          setState(() {
            draft.photos.add(copy!);
            draft.previews[copy] = preview;
          });
          retained = true;
        } finally {
          // Also covers cancel/sign-out during copying or reading a preview.
          if (copy != null && !retained) {
            await draft.remove(copy);
          }
        }
      }
    } catch (_) {
      if (available) {
        setState(
          () =>
              photoError = 'Не удалось выбрать фотографии. Попробуйте ещё раз',
        );
      }
    } finally {
      if (mounted) setState(() => selecting = false);
    }
  }

  void close(void Function(bool?) finish, bool? result) {
    if (!mounted || closing || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (result == true &&
        (!available ||
            selecting ||
            (widget.supplementing
                ? draft.photos.isEmpty
                : draft.photos.length < widget.needed))) {
      return;
    }
    closing = true;
    finish(result);
  }

  @override
  Widget build(BuildContext context) => FamilyActionDialog<bool>(
    // This local draft must remain usable offline. Network actions stay in
    // the repository's session-bound, durable queue.
    builder: (context, finish) => !widget.access.valid
        ? AlertDialog(
            scrollable: true,
            title: const Text('Нужно открыть окно заново'),
            content: const Text(
              'Семейный доступ изменился. Закройте это окно.',
            ),
            actions: [
              TextButton(
                onPressed: () => close(finish, null),
                child: const Text('Закрыть'),
              ),
            ],
          )
        : AlertDialog(
            scrollable: true,
            title: Text(
              widget.supplementing
                  ? 'Дослать фотографии'
                  : 'Отправить результат',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: spacedFormItems([
                Text(widget.title),
                if (!widget.supplementing)
                  LabeledInput(
                    label: 'Комментарий',
                    child: TextField(
                      controller: draft.note,
                      maxLength: 4000,
                      maxLines: 4,
                    ),
                  ),
                if (widget.supplementing)
                  Text(
                    'Уже отправлено фотографий: ${widget.existing}. Новые фото добавятся к этому результату.',
                  ),
                Text(
                  'Всего фотографий: ${widget.existing + draft.photos.length}',
                ),
                if (!widget.supplementing && widget.needed > 0)
                  Text('Нужно не меньше ${widget.needed} фотографий'),
                if (draft.photos.isNotEmpty)
                  const Text('Нажмите на фото, чтобы увеличить'),
                for (final path in draft.photos)
                  ListTile(
                    onTap: () {
                      if (!current) return;
                      widget.showPhotos(
                        draft.photos
                            .map(
                              (p) =>
                                  () async => File(p),
                            )
                            .toList(growable: false),
                        draft.photos.indexOf(path),
                      );
                    },
                    leading: Image.memory(
                      draft.previews[path]!,
                      cacheWidth: 96,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                    title: Text(
                      'Фото ${widget.existing + draft.photos.indexOf(path) + 1}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Убрать выбранное фото',
                      icon: const Icon(Icons.close),
                      onPressed: selecting
                          ? null
                          : () async {
                              if (!current || !draft.photos.contains(path)) {
                                return;
                              }
                              final removed = draft.remove(path);
                              setState(() {});
                              await removed;
                            },
                    ),
                  ),
                if (photoError != null)
                  Text(
                    photoError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                TextButton(
                  onPressed:
                      selecting || widget.existing + draft.photos.length >= 5
                      ? null
                      : pickPhotos,
                  child: Text(
                    selecting ? 'Добавляем фотографии…' : 'Добавить фото',
                  ),
                ),
                if (!widget.access.repository.online)
                  const Text(
                    'Результат сохранится на телефоне и отправится после подключения',
                  ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => close(finish, null),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed:
                    selecting ||
                        (widget.supplementing
                            ? draft.photos.isEmpty
                            : draft.photos.length < widget.needed)
                    ? null
                    : () => close(finish, true),
                child: Text(
                  widget.supplementing
                      ? 'Дослать фото'
                      : 'Отправить на проверку',
                ),
              ),
            ],
          ),
  );
}
