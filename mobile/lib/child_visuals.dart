import 'dart:async';

import 'package:flutter/material.dart';

import 'visuals.dart';
import 'design_system.dart';

/// All illustrated pixels and sprite frames come from ImageGen v2 assets.
class ChildArt extends StatelessWidget {
  final int index;
  final double size;
  const ChildArt(this.index, {super.key, this.size = 120});
  @override
  Widget build(BuildContext context) => RasterSprite(
    path: 'assets/generated/activities-v2.png',
    source: Rect.fromLTWH((index % 2) / 2, (index ~/ 2) / 2, .5, .5),
    normalized: true,
    size: size,
  );
}

class ChildMotion extends StatefulWidget {
  final bool celebrate;
  final double size;
  const ChildMotion({super.key, this.celebrate = false, this.size = 180});
  @override
  State<ChildMotion> createState() => _ChildMotionState();
}

class _ChildMotionState extends State<ChildMotion> with WidgetsBindingObserver {
  Timer? timer;
  int animationRequest = 0;
  bool awaitingPaint = false;
  int tick = 0;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    gameDesign.addListener(appearanceChanged);
  }

  void appearanceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    configure();
  }

  void configure() {
    timer?.cancel();
    final request = ++animationRequest;
    awaitingPaint = false;
    if (!foreground ||
        !TickerMode.valuesOf(context).enabled ||
        MediaQuery.disableAnimationsOf(context)) {
      tick = 0;
      return;
    }
    startTimer(request);
  }

  void startTimer(int request) {
    timer = Timer.periodic(const Duration(milliseconds: 160), (_) {
      if (!mounted || request != animationRequest || awaitingPaint) return;
      awaitingPaint = true;
      setState(() => tick = (tick + 1) % 30);
      // Preserve every authored pose even when the next UI frame is delayed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && request == animationRequest) awaitingPaint = false;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (mounted) {
      configure();
      setState(() {});
    }
  }

  @override
  void dispose() {
    animationRequest++;
    timer?.cancel();
    gameDesign.removeListener(appearanceChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Play six authored frames, then hold; no strobing or nonstop jumping.
    final sequence = widget.celebrate
        ? const [0, 1, 2, 3, 4, 5]
        : const [0, 1, 2, 3, 2, 1];
    final frame = MediaQuery.disableAnimationsOf(context)
        ? (widget.celebrate ? 5 : 0)
        : tick < 6
        ? sequence[tick]
        : (widget.celebrate ? 5 : 0);
    return RasterSprite(
      path:
          gameDesign.value?.animation ??
          'assets/generated/${widget.celebrate ? 'celebration' : 'helper-wave'}-v2.png',
      source: Rect.fromLTWH((frame % 3) / 3, (frame ~/ 3) / 2, 1 / 3, .5),
      normalized: true,
      size: widget.size,
    );
  }
}

class ChildHeader extends StatelessWidget {
  final int art;
  final String title, message;
  const ChildHeader({
    super.key,
    required this.art,
    required this.title,
    required this.message,
  });
  @override
  Widget build(BuildContext context) => gameDesign.value != null
      ? GameScene(title: title, description: message, compact: true)
      : Card(
          color: const Color(0xffd8edff),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final text = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(message),
                  ],
                );
                if (constraints.maxWidth < 300 ||
                    MediaQuery.textScalerOf(context).scale(16) > 24) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: ChildArt(art, size: 146)),
                      text,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: text),
                    ChildArt(art, size: 138),
                  ],
                );
              },
            ),
          ),
        );
}

class ChildSurface extends StatelessWidget {
  final bool enabled;
  final Widget child;
  const ChildSurface({super.key, required this.enabled, required this.child});
  @override
  Widget build(BuildContext context) => enabled
      ? Card(color: Colors.white, clipBehavior: Clip.antiAlias, child: child)
      : child;
}

class ChildSuccessDialog extends StatelessWidget {
  final String title, message;
  final int? coins;
  final VoidCallback? onClose;
  const ChildSuccessDialog({
    super.key,
    required this.title,
    required this.message,
    this.coins,
    this.onClose,
  });
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title, textAlign: TextAlign.center),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ChildMotion(celebrate: true, size: 220),
          if (coins != null && coins! > 0)
            Text(
              '+$coins монет',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: onClose ?? () => Navigator.pop(context),
        child: const Text('Здорово!'),
      ),
    ],
  );
}
