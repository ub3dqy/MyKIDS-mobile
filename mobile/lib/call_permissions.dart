import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'background.dart';

class CallPermissionNotice extends StatelessWidget {
  final BackgroundServices background;
  final bool details;
  const CallPermissionNotice({
    super.key,
    required this.background,
    this.details = false,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: background,
    builder: (context, _) {
      if (!details && !background.callsNeedSetup) {
        return const SizedBox.shrink();
      }
      final missing = background.callsNotificationsReady == false
          ? 'Уведомления о звонках выключены.'
          : background.callsFullScreenReady == false
          ? 'Звонок может быть слышен, но экран звонка поверх блокировки не разрешён.'
          : background.callsAlertsReady == false
          ? 'Для звонков выключены всплывающие уведомления.'
          : background.callsLockScreenReady == false
          ? 'Уведомления о звонках скрыты на заблокированном экране.'
          : background.callsMicrophoneReady == false
          ? 'Разрешите микрофон один раз на разблокированном телефоне, чтобы отвечать без разблокировки.'
          : background.callsNotificationsReady == null
          ? 'Состояние разрешений звонков пока не определено.'
          : 'Уведомления о звонках и показ экрана звонка разрешены.';
      Future<void> configure() async {
        try {
          await background.configureCalls();
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Откройте настройки телефона → Приложения → MyKIDS → Уведомления.',
                ),
              ),
            );
          }
        }
      }

      return Card(
        color: background.callsNeedSetup
            ? Theme.of(context).colorScheme.errorContainer
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                background.callsNeedSetup
                    ? 'Настройте экран входящего звонка'
                    : 'Входящие звонки',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(missing),
              if (details) ...[
                if (background.phoneModel != null)
                  Text(
                    '${background.phoneModel} · Android ${background.androidVersion ?? ''}',
                  ),
                const SizedBox(height: 6),
                const Text(
                  'Если слышен только звонок, разрешите для MyKIDS всплывающие уведомления и показ на экране блокировки в настройках телефона.',
                ),
                if (background.callsCameraReady == false) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Для ответа с видео разрешите камеру один раз на разблокированном телефоне.',
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        await background.enableCallCamera();
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Разрешите камеру в настройках телефона → MyKIDS → Разрешения.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Разрешить камеру для звонков'),
                  ),
                ],
                TextButton(
                  onPressed: () async {
                    try {
                      await background.checkCallPermissions();
                      final report = await nativeCalls
                          .invokeMapMethod<String, dynamic>('callDiagnostics');
                      if (report == null) {
                        throw StateError('No call diagnostics');
                      }
                      await Clipboard.setData(
                        ClipboardData(text: jsonEncode(report)),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Отчёт о звонках скопирован. В нём нет переписки, паролей и данных семьи.',
                            ),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Не удалось получить отчёт о звонках',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Скопировать отчёт о звонках'),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: configure,
                child: Text(
                  background.callsNeedSetup
                      ? 'Настроить звонки'
                      : 'Настройки звонков телефона',
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
