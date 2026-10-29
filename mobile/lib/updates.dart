import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'repository.dart';

const nativeUpdates = MethodChannel('ru.mykids/updates');

class UpdateOffer {
  final String role, package, version, sha, certificate, notes, directory;
  final int versionCode, bytes;
  final Uri url;
  const UpdateOffer({
    required this.role,
    required this.package,
    required this.version,
    required this.versionCode,
    required this.bytes,
    required this.sha,
    required this.certificate,
    required this.notes,
    required this.url,
    required this.directory,
  });
  String get fileName => 'MyKIDS-$version.apk';
}

class UpdateDownload {
  final String state;
  final double progress;
  final String? message;
  const UpdateDownload(this.state, this.progress, this.message);
  bool get active => state == 'running' || state == 'paused';
  bool get ready => state == 'ready';
}

class AppUpdates {
  final http.Client client;
  final MethodChannel channel;
  final Duration pollInterval;
  final detached = Completer<void>();
  bool cancelled = false;
  bool downloading = false;
  bool installing = false;
  int observation = 0;
  Completer<void>? pollTick, downloadDone;
  AppUpdates({
    http.Client? client,
    this.channel = nativeUpdates,
    this.pollInterval = const Duration(seconds: 1),
  }) : client = client ?? http.Client();

  void dispose() {
    cancelled = true;
    if (!detached.isCompleted) detached.complete();
    client.close();
    if (installing) {
      unawaited(channel.invokeMethod<void>('cancelUpdate').catchError((_) {}));
    }
  }

  void ensureActive() {
    if (cancelled) throw ApiFailure(499, 'Окно обновления закрыто');
  }

  // The setup role never selects an APK; all roles use the same distribution.
  Future<UpdateOffer?> check(Uri manifestUrl, String setupRole) async {
    if (manifestUrl.scheme != 'https' ||
        manifestUrl.userInfo.isNotEmpty ||
        manifestUrl.query.isNotEmpty ||
        manifestUrl.fragment.isNotEmpty) {
      throw ApiFailure(400, 'Не удалось проверить обновление');
    }
    final info = await channel.invokeMapMethod<String, dynamic>('appInfo');
    ensureActive();
    const package = 'ru.mykids.mykids_family.parent';
    if (info == null ||
        info['package'] != package ||
        info['versionCode'] is! int ||
        info['signerSha256'] is! String ||
        info['updateDirectory'] is! String) {
      throw ApiFailure(400, 'Не удалось определить версию приложения');
    }
    final request = http.Request('GET', manifestUrl)..followRedirects = false;
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 20));
    ensureActive();
    if (response.statusCode != 200 || (response.contentLength ?? 0) > 32768) {
      throw ApiFailure(502, 'Не удалось проверить обновление');
    }
    final body = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      ensureActive();
      if (body.length + chunk.length > 32768) {
        throw ApiFailure(502, 'Не удалось проверить обновление');
      }
      body.addAll(chunk);
    }
    final dynamic document = jsonDecode(utf8.decode(body));
    if (document is! Map ||
        document['schema'] != 1 ||
        document['apps'] is! List) {
      throw ApiFailure(502, 'Не удалось проверить обновление');
    }
    final entries = (document['apps'] as List)
        .whereType<Map>()
        .where((entry) => entry['role'] == 'family')
        .toList();
    if (entries.length != 1) {
      throw ApiFailure(502, 'Не удалось проверить обновление');
    }
    final entry = entries.single;
    final version = entry['version'];
    final code = entry['version_code'];
    final bytes = entry['bytes'];
    final sha = entry['sha256'];
    final certificate = entry['certificate_sha256'];
    final notes = entry['notes'];
    if (entry['package'] != package ||
        version is! String ||
        !RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$').hasMatch(version) ||
        code is! int ||
        code < 1 ||
        code > 2100000000 ||
        bytes is! int ||
        bytes < 1 ||
        bytes > 512 * 1024 * 1024 ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        certificate != info['signerSha256'] ||
        notes is! String ||
        notes.length > 1000) {
      throw ApiFailure(502, 'Обновление не соответствует этому приложению');
    }
    final url = Uri.tryParse(
      entry['url'] is String ? entry['url'] as String : '',
    );
    final expected = manifestUrl.replace(
      path: '/downloads/MyKIDS-$version.apk',
    );
    if (url != expected) throw ApiFailure(502, 'Неверный адрес обновления');
    if (code <= (info['versionCode'] as int)) return null;
    return UpdateOffer(
      role: 'family',
      package: package,
      version: version,
      versionCode: code,
      bytes: bytes,
      sha: sha,
      certificate: certificate as String,
      notes: notes,
      url: expected,
      directory: info['updateDirectory'] as String,
    );
  }

  Map<String, Object> arguments(UpdateOffer offer) => {
    'fileName': offer.fileName,
    'versionCode': offer.versionCode,
    'bytes': offer.bytes,
    'sha256': offer.sha,
    'url': offer.url.toString(),
  };

  Future<UpdateDownload> downloadState(
    UpdateOffer offer, {
    bool start = false,
  }) async {
    ensureActive();
    final state = await channel.invokeMapMethod<String, dynamic>(
      start ? 'startDownload' : 'downloadStatus',
      arguments(offer),
    );
    ensureActive();
    final name = state?['state'];
    if (!['idle', 'running', 'paused', 'ready', 'failed'].contains(name)) {
      throw ApiFailure(502, 'Не удалось узнать состояние загрузки');
    }
    final received = state?['received'];
    final total = state?['bytes'];
    final progress = received is int && total == offer.bytes
        ? (received / offer.bytes).clamp(0.0, 1.0)
        : 0.0;
    return UpdateDownload(
      name as String,
      progress,
      state?['message'] is String ? state!['message'] as String : null,
    );
  }

  Future<void> download(
    UpdateOffer offer,
    ValueChanged<double> progress, {
    bool start = true,
    ValueChanged<UpdateDownload>? onState,
  }) async {
    ensureActive();
    if (downloading) throw ApiFailure(409, 'Обновление уже скачивается');
    downloading = true;
    final current = ++observation;
    final done = downloadDone = Completer<void>();
    try {
      var state = await downloadState(offer, start: start);
      while (true) {
        ensureActive();
        if (current != observation) throw ApiFailure(499, 'Загрузка отменена');
        progress(state.progress);
        onState?.call(state);
        if (state.ready) return;
        if (!state.active) {
          throw ApiFailure(
            502,
            state.message ?? 'Загрузка остановлена. Нажмите «Скачать и обновить», чтобы повторить.',
          );
        }
        // Closing a dialog only detaches observation, leaving Android's transfer intact.
        final tick = Completer<void>();
        pollTick = tick;
        final timer = Timer(pollInterval, tick.complete);
        try {
          await Future.any([tick.future, detached.future]);
        } finally {
          timer.cancel();
        }
        ensureActive();
        state = await downloadState(offer);
      }
    } finally {
      downloading = false;
      done.complete();
    }
  }

  Future<void> cancelDownload(UpdateOffer offer) async {
    ensureActive();
    observation++;
    if (pollTick != null && !pollTick!.isCompleted) pollTick!.complete();
    try {
      await channel.invokeMethod<void>('cancelDownload', arguments(offer));
    } finally {
      await downloadDone?.future;
    }
  }

  Future<String> install(UpdateOffer offer) async {
    ensureActive();
    installing = true;
    try {
      final state = await channel.invokeMethod<String>('installUpdate', {
        'fileName': offer.fileName,
        'versionCode': offer.versionCode,
        'bytes': offer.bytes,
        'sha256': offer.sha,
      });
      ensureActive();
      return state ?? 'failed';
    } finally {
      installing = false;
    }
  }
}

class UpdateCheckDialog extends StatefulWidget {
  final Future<UpdateOffer?> check;
  const UpdateCheckDialog({super.key, required this.check});
  @override
  State<UpdateCheckDialog> createState() => _UpdateCheckDialogState();
}

class _UpdateCheckDialogState extends State<UpdateCheckDialog> {
  bool loading = true;
  UpdateOffer? offer;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(finish());
  }

  Future<void> finish() async {
    try {
      final result = await widget.check;
      if (mounted) setState(() => offer = result);
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is ApiFailure
              ? failure.message
              : 'Проверьте интернет и попробуйте ещё раз.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !loading,
    child: offer != null
        ? UpdateDialog(offer: offer!)
        : AlertDialog(
            title: Text(
              loading
                  ? 'Проверка обновлений'
                  : error != null
                  ? 'Не удалось проверить обновления'
                  : 'Обновлений нет',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (loading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    loading
                        ? 'Проверяем актуальность версии…'
                        : error ??
                              'У вас установлена актуальная версия MyKIDS.',
                  ),
                ],
              ),
            ),
            actions: [
              if (!loading)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Понятно'),
                ),
            ],
          ),
  );
}

class UpdateDialog extends StatefulWidget {
  final UpdateOffer offer;
  const UpdateDialog({super.key, required this.offer});
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final updater = AppUpdates();
  bool busy = true, downloaded = false, transferring = false, paused = false;
  double progress = 0;
  String? message;
  int operation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(restore());
  }

  @override
  void dispose() {
    updater.dispose();
    super.dispose();
  }

  String failureMessage(Object error) => error is ApiFailure
      ? error.message
      : error is PlatformException && error.message != null
      ? error.message!
      : 'Не удалось обновить приложение. Проверьте интернет и свободное место';

  Future<void> restore() async {
    final current = ++operation;
    try {
      final state = await updater.downloadState(widget.offer);
      if (!mounted || operation != current) return;
      if (state.active) {
        await observe(current, start: false);
      } else {
        setState(() {
          busy = false;
          downloaded = state.ready;
          progress = state.progress;
          message = state.ready
              ? 'Обновление скачано. Нажмите «Установить».'
              : state.message;
        });
      }
    } catch (error) {
      if (mounted && current == operation) {
        setState(() {
          busy = false;
          transferring = false;
          message = failureMessage(error);
        });
      }
    }
  }

  Future<void> observe(int current, {required bool start}) async {
    setState(() {
      busy = true;
      transferring = true;
      message = null;
    });
    await updater.download(
      widget.offer,
      (value) {
        if (mounted && current == operation) setState(() => progress = value);
      },
      start: start,
      onState: (state) {
        if (mounted && current == operation) {
          setState(() => paused = state.state == 'paused');
        }
      },
    );
    if (mounted && current == operation) {
      setState(() {
        busy = false;
        transferring = false;
        downloaded = true;
        message = 'Обновление скачано. Нажмите «Установить».';
      });
    }
  }

  Future<void> update() async {
    if (busy) return;
    final current = ++operation;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (!downloaded) {
        await observe(current, start: true);
        return;
      }
      final state = await updater.install(widget.offer);
      if (!mounted || current != operation) return;
      setState(
        () => message = state == 'permission_required'
            ? 'Разрешите установку обновлений из MyKIDS, вернитесь сюда и нажмите «Установить».'
            : state == 'installer_opened'
            ? 'Подтвердите обновление в окне Android. Данные семьи сохранятся.'
            : state == 'ready'
            ? 'Обновление скачано. Нажмите «Установить» после разблокировки телефона.'
            : 'Не удалось открыть установку обновления',
      );
    } catch (error) {
      // Android may remove a partial or damaged APK while the dialog is open.
      // Recover the download action without touching the family's local data.
      UpdateDownload? state;
      if (downloaded && mounted && current == operation) {
        try {
          state = await updater.downloadState(widget.offer);
        } catch (_) {
          // A failed integrity check already proves this APK cannot be used.
        }
      }
      if (mounted && current == operation) {
        setState(() {
          if (state != null) {
            downloaded = state.ready;
            progress = state.progress;
          } else if (error is PlatformException &&
              error.code == 'UPDATE_INVALID') {
            downloaded = false;
            progress = 0;
          }
          message =
              !downloaded &&
                  error is PlatformException &&
                  error.code == 'UPDATE_INVALID'
              ? 'Файл обновления недоступен или повреждён. Скачайте обновление ещё раз.'
              : failureMessage(error);
        });
      }
    } finally {
      if (mounted && current == operation) {
        setState(() {
          busy = false;
          transferring = false;
        });
      }
    }
  }

  Future<void> cancel() async {
    final current = ++operation;
    setState(() => busy = true);
    try {
      await updater.cancelDownload(widget.offer);
      if (mounted && current == operation) {
        setState(() {
          busy = false;
          downloaded = false;
          transferring = false;
          paused = false;
          progress = 0;
          message = 'Загрузка отменена';
        });
      }
    } catch (error) {
      if (mounted && current == operation) {
        setState(() {
          busy = false;
          transferring = false;
          message = failureMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      downloaded ? 'Обновление готово' : 'Доступно обновление MyKIDS',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Версия ${widget.offer.version} · ${(widget.offer.bytes / 1000000).toStringAsFixed(1)} МБ',
          ),
          const SizedBox(height: 12),
          Text(widget.offer.notes),
          if (busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: transferring ? progress : null),
            if (transferring) ...[
              Text('${(progress * 100).round()} %'),
              const SizedBox(height: 8),
              Text(
                paused
                    ? 'Android ожидает подключения для продолжения загрузки.'
                    : 'Можно закрыть это окно или заблокировать телефон. Загрузка продолжится.',
              ),
            ],
          ],
          if (message != null) ...[const SizedBox(height: 12), Text(message!)],
        ],
      ),
    ),
    actions: [
      if (transferring)
        TextButton(onPressed: cancel, child: const Text('Отменить загрузку')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(transferring ? 'Скрыть' : 'Позже'),
      ),
      FilledButton(
        onPressed: busy ? null : update,
        child: Text(downloaded ? 'Установить' : 'Скачать и обновить'),
      ),
    ],
  );
}
