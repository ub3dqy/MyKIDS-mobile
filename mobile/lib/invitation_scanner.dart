import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'invitation.dart';
import 'repository.dart';

class InvitationScanner extends StatefulWidget {
  final String role;
  const InvitationScanner({super.key, required this.role});
  @override
  State<InvitationScanner> createState() => _InvitationScannerState();
}

class _InvitationScannerState extends State<InvitationScanner>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  Future<void> cameraOperation = Future<void>.value();
  bool wantCamera = true, finished = false, routeVisible = false;
  String? message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => camera(true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) == true;
    if (visible != routeVisible) {
      routeVisible = visible;
      camera(wantCamera);
    }
  }

  bool get canUseCamera =>
      mounted &&
      !finished &&
      ModalRoute.of(context)?.isCurrent == true &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void camera(bool wanted) {
    wantCamera = wanted;
    // Serialize lifecycle operations; a delayed stop must not stop a new session.
    cameraOperation = cameraOperation
        .then((_) async {
          if (!mounted || finished) return;
          if (wantCamera && canUseCamera) {
            await controller.start();
            if (!wantCamera || !canUseCamera) {
              await controller.stop();
            }
          } else {
            await controller.stop();
          }
        })
        .catchError((Object error) {
          if (mounted && !finished) {
            setState(
              () => message =
                  'Не удалось открыть камеру. Можно ввести код вручную.',
            );
          }
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    camera(state == AppLifecycleState.resumed);
  }

  Future<void> detected(BarcodeCapture capture) async {
    if (!mounted ||
        finished ||
        !wantCamera ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    ApiFailure? rejection;
    for (final barcode in capture.barcodes) {
      final data = barcode.rawValue;
      if (data == null) continue;
      try {
        final invitation = Invitation.parse(data, expectedRole: widget.role);
        finished = true;
        wantCamera = false;
        await cameraOperation;
        await controller.stop();
        if (mounted &&
            ModalRoute.of(context)?.isCurrent == true &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          Navigator.pop(context, invitation);
        } else if (mounted) {
          // A covering route interrupted this scan. Read a fresh code when
          // visible again instead of returning a token to the covering route.
          finished = false;
          camera(true);
        }
        return;
      } on ApiFailure catch (error) {
        rejection = error;
      } catch (_) {
        if (mounted) {
          setState(
            () => message = 'Не удалось завершить сканирование. Вернитесь и попробуйте ещё раз.',
          );
        }
        return;
      }
    }
    if (mounted && rejection != null && message != rejection.message) {
      setState(() => message = rejection!.message);
    }
  }

  void enterManually() {
    if (!mounted || finished || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    finished = true;
    wantCamera = false;
    Navigator.pop(context);
  }

  @override
  void dispose() {
    finished = true;
    wantCamera = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      cameraOperation.then((_) => controller.dispose()).catchError((_) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Сканировать приглашение')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Наведите камеру на QR-код в приложении родителя.'),
          ),
          Expanded(
            child: MobileScanner(
              controller: controller,
              useAppLifecycleState: false,
              onDetect: detected,
              onDetectError: (_, _) {
                if (mounted && !finished) {
                  setState(
                    () => message =
                        'Не удалось прочитать код. Наведите камеру ещё раз.',
                  );
                }
              },
              errorBuilder: (context, error) => Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error.errorCode ==
                                MobileScannerErrorCode.permissionDenied
                            ? 'Разрешите MyKIDS доступ к камере, чтобы прочитать приглашение.'
                            : 'Камера недоступна. Можно вернуться и ввести код вручную.',
                      ),
                      TextButton(
                        onPressed: () {
                          if (canUseCamera) unawaited(openAppSettings());
                        },
                        child: const Text('Настройки камеры'),
                      ),
                      TextButton(
                        onPressed: () => camera(true),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (message != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(message!)),
          TextButton(
            onPressed: enterManually,
            child: const Text('Ввести код вручную'),
          ),
        ],
      ),
    ),
  );
}
