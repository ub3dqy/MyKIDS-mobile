import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Additional existing task requirements do not alter the approved play pages.
Future<List<String>?> choosePlayPhotos(
  BuildContext context,
  Map<String, dynamic> task,
) => showDialog<List<String>>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      _Photos(requiredCount: (task['required_photos'] as int? ?? 1)),
);

class _Photos extends StatefulWidget {
  final int requiredCount;
  const _Photos({required this.requiredCount});
  @override
  State<_Photos> createState() => _PhotosState();
}

class _PhotosState extends State<_Photos> {
  final photos = <String>[];
  bool selecting = false;
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Фотографии результата'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Для этого задания нужно фото: ${photos.length} из ${widget.requiredCount}.',
        ),
        for (var i = 0; i < photos.length; i++)
          ListTile(
            leading: Image.file(
              File(photos[i]),
              width: 48,
              height: 48,
              cacheWidth: 96,
              fit: BoxFit.cover,
            ),
            title: Text('Фото ${i + 1}'),
            trailing: IconButton(
              tooltip: 'Убрать выбранное фото',
              onPressed: selecting
                  ? null
                  : () => setState(() => photos.removeAt(i)),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        if (error != null) Text(error!),
        OutlinedButton(
          onPressed: selecting || photos.length >= 5
              ? null
              : () async {
                  setState(() {
                    selecting = true;
                    error = null;
                  });
                  try {
                    final remaining = 5 - photos.length;
                    final selected = remaining == 1
                        ? [
                            ?await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 2048,
                              maxHeight: 2048,
                              imageQuality: 88,
                            ),
                          ]
                        : await ImagePicker().pickMultiImage(
                            maxWidth: 2048,
                            maxHeight: 2048,
                            imageQuality: 88,
                            limit: remaining,
                          );
                    if (mounted) {
                      setState(
                        () => photos.addAll(
                          selected
                              .take(remaining)
                              .map((p) => p.path)
                              .where((p) => !photos.contains(p)),
                        ),
                      );
                    }
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => error =
                            'Не удалось выбрать фотографии. Попробуй ещё раз.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => selecting = false);
                  }
                },
          child: Text(selecting ? 'Добавляем фотографии…' : 'Добавить фото'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: selecting ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: selecting || photos.length < widget.requiredCount
            ? null
            : () => Navigator.pop(context, List<String>.of(photos)),
        child: const Text('Отправить на проверку'),
      ),
    ],
  );
}
