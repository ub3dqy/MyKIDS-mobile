import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_system.dart';
import '../visuals.dart';
import 'engagement_model.dart';

/// Measured full silhouettes, not assumed grid cells. Original PNG is unedited.
const playItemSources = <Rect>[
  Rect.fromLTRB(26, 36, 430, 376),
  Rect.fromLTRB(454, 29, 842, 393),
  Rect.fromLTRB(875, 42, 1220, 380),
  Rect.fromLTRB(26, 474, 443, 773),
  Rect.fromLTRB(481, 407, 855, 796),
  Rect.fromLTRB(964, 396, 1167, 807),
  Rect.fromLTRB(40, 801, 421, 1214),
  Rect.fromLTRB(516, 802, 748, 1213),
  Rect.fromLTRB(829, 830, 1233, 1211),
];

class PlayItemArt extends StatelessWidget {
  final PlayItem item;
  final double size;
  const PlayItemArt(this.item, {super.key, this.size = 80});
  @override
  Widget build(BuildContext context) => RasterSprite(
    path: 'assets/designs/engagement-items.png',
    source: playItemSources[item.artwork],
    size: size,
    preserveAspectRatio: true,
  );
}

class EngagementAvatar extends StatefulWidget {
  final String hero;
  final Set<String> worn;
  final double size;
  final bool animate, celebrate;
  const EngagementAvatar({
    super.key,
    required this.hero,
    this.worn = const {},
    this.size = 160,
    this.animate = true,
    this.celebrate = false,
  });
  @override
  State<EngagementAvatar> createState() => _EngagementAvatarState();
}

class _EngagementAvatarState extends State<EngagementAvatar>
    with WidgetsBindingObserver {
  Timer? timer;
  int artworkRequest = 0;
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
    if (mounted && widget.hero == 'auto' && gameDesign.value != null) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    configure();
  }

  @override
  void didUpdateWidget(EngagementAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hero != widget.hero ||
        oldWidget.animate != widget.animate ||
        oldWidget.celebrate != widget.celebrate) {
      tick = 0;
      configure();
    }
  }

  void configure() {
    timer?.cancel();
    final request = ++artworkRequest;
    awaitingPaint = false;
    if (!foreground ||
        !widget.animate ||
        !TickerMode.valuesOf(context).enabled ||
        MediaQuery.disableAnimationsOf(context)) {
      tick = 0;
      return;
    }
    final design = GameDesign.byId(
      widget.hero == 'auto' ? gameDesign.value!.id : widget.hero,
    )!;
    if (!rasterArtworkIsReady(design.animation)) {
      unawaited(startAfterArtwork(design.animation, request));
      return;
    }
    startTimer(request);
  }

  void startTimer(int request) {
    timer = Timer.periodic(const Duration(milliseconds: 160), (_) {
      if (!mounted || request != artworkRequest || awaitingPaint) return;
      awaitingPaint = true;
      setState(() => tick = (tick + 1) % 30);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && request == artworkRequest) awaitingPaint = false;
      });
    });
  }

  Future<void> startAfterArtwork(String path, int request) async {
    try {
      await precacheRasterArtwork([path]);
    } catch (error, stack) {
      if (mounted && request == artworkRequest) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'MyKIDS hero artwork',
          ),
        );
      }
      return;
    }
    if (!mounted || request != artworkRequest) return;
    setState(() => tick = 0);
    // Give the decoded atlas its first actual frame before advancing it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && request == artworkRequest) startTimer(request);
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
    artworkRequest++;
    timer?.cancel();
    gameDesign.removeListener(appearanceChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final design = GameDesign.byId(
      widget.hero == 'auto' ? gameDesign.value!.id : widget.hero,
    )!;
    final sequence = widget.celebrate
        ? const [0, 1, 2, 3, 4, 5]
        : const [0, 1, 2, 3, 2, 1];
    final still = !widget.animate || MediaQuery.disableAnimationsOf(context);
    final frame = still
        ? (widget.celebrate ? 5 : 0)
        : tick < 6
        ? sequence[tick]
        : (widget.celebrate ? 5 : 0);
    final headset = switch (design.id) {
      'blocks' => const Rect.fromLTWH(.285, .055, .43, .34),
      'comic' => const Rect.fromLTWH(.265, .065, .47, .35),
      'islands' => const Rect.fromLTWH(.29, .075, .48, .34),
      _ => const Rect.fromLTWH(.255, .065, .49, .36),
    };
    Widget accessory(String id, Rect rect) => Positioned(
      left: rect.left * widget.size,
      top: rect.top * widget.size,
      width: rect.width * widget.size,
      height: rect.height * widget.size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: PlayItemArt(playItem(id), size: 180),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.worn.contains('cape'))
              accessory('cape', const Rect.fromLTWH(.21, .28, .64, .60)),
            Positioned.fill(
              child: RasterSprite(
                path: design.animation,
                normalized: true,
                source: Rect.fromLTWH(frame % 3 / 3, frame ~/ 3 / 2, 1 / 3, .5),
                size: widget.size,
                preserveAspectRatio: true,
              ),
            ),
            if (widget.worn.contains('headphones'))
              accessory('headphones', headset),
            if (widget.worn.contains('badge'))
              accessory('badge', const Rect.fromLTWH(.49, .46, .11, .11)),
          ],
        ),
      ),
    );
  }
}

class PlayRoom extends StatelessWidget {
  final EngagementController controller;
  final ValueChanged<int>? onSlot;
  const PlayRoom({super.key, required this.controller, this.onSlot});
  @override
  Widget build(BuildContext context) {
    final design = gameDesign.value!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(design.radius),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            const slots = [
              Rect.fromLTWH(.025, .47, .26, .47),
              Rect.fromLTWH(.70, .40, .27, .44),
              Rect.fromLTWH(.73, .66, .24, .31),
            ];
            return Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/designs/engagement-room-${design.id}.png',
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                for (var i = 0; i < 3; i++)
                  Positioned(
                    left: slots[i].left * w,
                    top: slots[i].top * h,
                    width: slots[i].width * w,
                    height: slots[i].height * h,
                    child: Semantics(
                      label:
                          'Место ${i + 1}: ${controller.state.room[i] == null ? 'пусто' : playItem(controller.state.room[i]!).name}',
                      button: onSlot != null,
                      child: InkWell(
                        onTap: onSlot == null ? null : () => onSlot!(i),
                        borderRadius: BorderRadius.circular(14),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: onSlot != null
                                ? Colors.white.withValues(alpha: .12)
                                : null,
                            border: onSlot != null
                                ? Border.all(
                                    color: Colors.white.withValues(alpha: .9),
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: controller.state.room[i] == null
                              ? onSlot == null
                                    ? const SizedBox()
                                    : const Center(
                                        child: Icon(
                                          Icons.add_circle,
                                          size: 38,
                                          color: Colors.white,
                                        ),
                                      )
                              : FittedBox(
                                  fit: BoxFit.contain,
                                  child: PlayItemArt(
                                    playItem(controller.state.room[i]!),
                                    size: 140,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: w * .30,
                  bottom: h * .045,
                  width: w * .40,
                  height: h * .78,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: EngagementAvatar(
                      hero: controller.state.hero,
                      worn: controller.state.worn,
                      size: math.min(w * .40, h * .78),
                    ),
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
