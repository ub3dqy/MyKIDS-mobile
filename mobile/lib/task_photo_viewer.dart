import 'dart:io';

import 'package:flutter/material.dart';

import 'repository.dart';

/// Loads one full-size photo at a time, without keeping a thumbnail for zooming.
class TaskPhotoViewer extends StatefulWidget {
  final FamilyRepository repository;
  final List<Future<File> Function()> photos;
  final int initialIndex;
  final String _session, _endpoint, _user;
  final int _generation;

  TaskPhotoViewer({
    super.key,
    required this.repository,
    required this.photos,
    this.initialIndex = 0,
  }) : _session = repository.sessionTag,
       _endpoint = repository.endpoint,
       _user = repository.userId,
       _generation = repository.generation,
       assert(photos.isNotEmpty),
       assert(initialIndex >= 0 && initialIndex < photos.length);

  @override
  State<TaskPhotoViewer> createState() => _TaskPhotoViewerState();
}

class _TaskPhotoViewerState extends State<TaskPhotoViewer> {
  final _transform = TransformationController();
  final _loaded = <int, Future<File>>{};
  late final FamilyRepository _repository;
  late final String _session, _endpoint, _user;
  late final int _generation;
  late int _index;
  Offset _doubleTapPosition = Offset.zero;
  Size _viewport = Size.zero;
  bool _closing = false;

  bool get _hasAccess =>
      identical(widget.repository, _repository) &&
      _repository.signedIn &&
      _repository.sessionTag == _session &&
      _repository.endpoint == _endpoint &&
      _repository.generation == _generation &&
      _repository.userId == _user;

  bool get _canInteract =>
      mounted &&
      !_closing &&
      _hasAccess &&
      ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _session = widget._session;
    _endpoint = widget._endpoint;
    _generation = widget._generation;
    _user = widget._user;
    _index = widget.initialIndex;
    _repository.addListener(_accessChanged);
  }

  @override
  void didUpdateWidget(covariant TaskPhotoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.repository, _repository)) _accessChanged();
  }

  void _accessChanged() {
    if (!mounted || _hasAccess || _closing) return;
    setState(() => _closing = true);
    _removeRoute();
  }

  void _removeRoute() {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && route != null && route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    _repository.removeListener(_accessChanged);
    _transform.dispose();
    super.dispose();
  }

  void _changePhoto(int index) {
    if (!_canInteract || index < 0 || index >= widget.photos.length) return;
    _transform.value = Matrix4.identity();
    setState(() => _index = index);
  }

  void _zoom(double scale, Offset position) {
    if (!_canInteract) return;
    final target = scale.clamp(1.0, 8.0);
    final scene = _transform.toScene(position);
    // Keep the touched point still when zooming; the rest can be dragged.
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (position.dx - scene.dx * target).clamp(
          _viewport.width * (1 - target),
          0.0,
        ),
        (position.dy - scene.dy * target).clamp(
          _viewport.height * (1 - target),
          0.0,
        ),
        0,
        1,
      )
      ..scaleByDouble(target, target, 1, 1);
    if (target == 1) _transform.value = Matrix4.identity();
  }

  void _retry() {
    if (!_canInteract) return;
    setState(() {
      _loaded.remove(_index);
    });
  }

  void _resetZoom() {
    if (_canInteract) _transform.value = Matrix4.identity();
  }

  void _close() {
    if (!_canInteract) return;
    setState(() => _closing = true);
    Navigator.of(context).pop();
  }

  Widget _unavailable() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Не удалось открыть фотографию',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _retry, child: const Text('Повторить')),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess || _closing) {
      if (!_closing) {
        _closing = true;
        _removeRoute();
      }
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: Text(
          'Фото ${_index + 1} из ${widget.photos.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Закрыть фотографию',
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<File>(
          key: ValueKey(_index),
          future: _loaded.putIfAbsent(_index, widget.photos[_index]),
          builder: (context, snapshot) {
            if (!_hasAccess) return const SizedBox.shrink();
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) return _unavailable();
            return LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                if (_viewport != Size.zero && _viewport != size) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _hasAccess && _viewport == size) {
                      _transform.value = Matrix4.identity();
                    }
                  });
                }
                _viewport = size;
                return GestureDetector(
                  onDoubleTapDown: (details) =>
                      _doubleTapPosition = details.localPosition,
                  onDoubleTap: () => _zoom(
                    _transform.value.getMaxScaleOnAxis() > 1.01 ? 1 : 3,
                    _doubleTapPosition,
                  ),
                  child: InteractiveViewer(
                    key: const ValueKey('task-photo-zoom'),
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: 8,
                    child: SizedBox.expand(
                      child: Image.file(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        semanticLabel: 'Фото ${_index + 1}',
                        errorBuilder: (context, error, stack) => _unavailable(),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Разведите два пальца или нажмите дважды',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (widget.photos.length > 1)
                    IconButton(
                      tooltip: 'Предыдущее фото',
                      color: Colors.white,
                      disabledColor: Colors.white30,
                      onPressed: _index > 0
                          ? () => _changePhoto(_index - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                  IconButton(
                    tooltip: 'Уменьшить',
                    color: Colors.white,
                    onPressed: () => _zoom(
                      _transform.value.getMaxScaleOnAxis() / 1.5,
                      _viewport.center(Offset.zero),
                    ),
                    icon: const Icon(Icons.zoom_out),
                  ),
                  IconButton(
                    tooltip: 'Показать целиком',
                    color: Colors.white,
                    onPressed: _resetZoom,
                    icon: const Icon(Icons.fit_screen),
                  ),
                  IconButton(
                    tooltip: 'Увеличить',
                    color: Colors.white,
                    onPressed: () => _zoom(
                      _transform.value.getMaxScaleOnAxis() * 1.5,
                      _viewport.center(Offset.zero),
                    ),
                    icon: const Icon(Icons.zoom_in),
                  ),
                  if (widget.photos.length > 1)
                    IconButton(
                      tooltip: 'Следующее фото',
                      color: Colors.white,
                      disabledColor: Colors.white30,
                      onPressed: _index < widget.photos.length - 1
                          ? () => _changePhoto(_index + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
