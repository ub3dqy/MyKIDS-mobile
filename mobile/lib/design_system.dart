import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The preview and the family application use these exact specifications.
/// Null preserves the currently published appearance until a design is chosen.
final gameDesign = ValueNotifier<GameDesign?>(
  GameDesign.byId(const String.fromEnvironment('MYKIDS_DESIGN')),
);

@immutable
class GameDesign {
  final String id, name, description;
  final Color background,
      surface,
      ink,
      accent,
      soft,
      reward,
      outline,
      navigation;
  final double radius, borderWidth, lift;
  const GameDesign({
    required this.id,
    required this.name,
    required this.description,
    required this.background,
    required this.surface,
    required this.ink,
    required this.accent,
    required this.soft,
    required this.reward,
    required this.outline,
    required this.navigation,
    required this.radius,
    required this.borderWidth,
    required this.lift,
  });

  static const all = <GameDesign>[
    GameDesign(
      id: 'blocks',
      name: 'Кубический мир',
      description: 'Блочные формы, крупные детали, свой герой',
      background: Color(0xffedf5ff),
      surface: Colors.white,
      ink: Color(0xff17365c),
      accent: Color(0xff245caa),
      soft: Color(0xffdceafa),
      reward: Color(0xffffd361),
      outline: Color(0xffaac5e7),
      navigation: Color(0xff233e65),
      radius: 12,
      borderWidth: 1.5,
      lift: 3,
    ),
    GameDesign(
      id: 'squad',
      name: 'Звёздный отряд',
      description: 'Аркадная команда, космос и энергия',
      background: Color(0xffedf4ff),
      surface: Colors.white,
      ink: Color(0xff183865),
      accent: Color(0xff245bb0),
      soft: Color(0xffdaebff),
      reward: Color(0xffffcd57),
      outline: Color(0xffbacff0),
      navigation: Color(0xff152c54),
      radius: 19,
      borderWidth: 1,
      lift: 4,
    ),
    GameDesign(
      id: 'comic',
      name: 'Комикс-клуб',
      description: 'Контрастный комикс и выразительные наклейки',
      background: Color(0xfffff8dc),
      surface: Color(0xfffffef9),
      ink: Color(0xff263d84),
      accent: Color(0xff294996),
      soft: Color(0xfff7e89a),
      reward: Color(0xffffdf63),
      outline: Color(0xff304887),
      navigation: Color(0xfffffef8),
      radius: 12,
      borderWidth: 2.2,
      lift: 3,
    ),
    GameDesign(
      id: 'workshop',
      name: 'Мастерская героев',
      description: 'Объёмные детали, робот и конструктор',
      background: Color(0xffedf4f7),
      surface: Color(0xfffcfefe),
      ink: Color(0xff244b5c),
      accent: Color(0xff28687d),
      soft: Color(0xffd6e9ee),
      reward: Color(0xffffb960),
      outline: Color(0xffbbd4df),
      navigation: Color(0xff254d61),
      radius: 26,
      borderWidth: 1.4,
      lift: 5,
    ),
    GameDesign(
      id: 'islands',
      name: 'Остров приключений',
      description: 'Мир островов и маленькие шаги к цели',
      background: Color(0xffeaf7f6),
      surface: Colors.white,
      ink: Color(0xff1b515a),
      accent: Color(0xff246a76),
      soft: Color(0xffcfebea),
      reward: Color(0xffffd16d),
      outline: Color(0xffb9deda),
      navigation: Color(0xfffbfefe),
      radius: 21,
      borderWidth: 1.2,
      lift: 3,
    ),
  ];

  static GameDesign? byId(String id) {
    for (final design in all) {
      if (design.id == id) return design;
    }
    return null;
  }

  String get scene => 'assets/designs/$id-scene.png';
  String get animation => id == 'squad' || id == 'comic'
      ? 'assets/designs/$id-motion-clean.png'
      : 'assets/designs/$id-motion.png';
  bool get lightNavigation => id == 'comic' || id == 'islands';
  Color get onNavigation => lightNavigation ? ink : Colors.white;
  Color get headerBackground => id == 'squad' ? navigation : background;
  Color get onHeader => id == 'squad' ? Colors.white : ink;
  Color get muted => Color.lerp(ink, background, .28)!;

  // The approved 412px images recorded physical shadows at Android density
  // 420dpi before exporting at 1px per logical pixel. Preserve that visible
  // depth in the real UI; it must not change with the user's screen density.
  double get shadowLift => lift * (420 / 160);

  ThemeData theme(bool child) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: outline, width: borderWidth),
    );
    final scheme = ColorScheme.fromSeed(seedColor: accent).copyWith(
      primary: accent,
      onPrimary: Colors.white,
      secondary: reward,
      onSecondary: ink,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: soft,
      outline: outline,
    );
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'MyKidsNunito',
      colorScheme: scheme,
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(
            bodyMedium: TextStyle(
              fontFamily: 'MyKidsNunito',
              color: ink,
              fontSize: 16,
              height: 1.4,
            ),
            bodyLarge: TextStyle(
              fontFamily: 'MyKidsNunito',
              color: ink,
              fontSize: 17,
              height: 1.4,
            ),
            titleLarge: TextStyle(
              fontFamily: 'MyKidsNunito',
              color: ink,
              fontSize: 21,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
            headlineSmall: TextStyle(
              fontFamily: 'MyKidsNunito',
              color: ink,
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: headerBackground,
        foregroundColor: onHeader,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'MyKidsNunito',
          color: onHeader,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: outline,
        elevation: shadowLift,
        shape: shape,
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: reward,
          foregroundColor: ink,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          elevation: shadowLift,
          shadowColor: outline,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(math.min(radius, 18)),
            side: BorderSide(
              color: Color.lerp(reward, ink, .3)!,
              width: borderWidth,
            ),
          ),
          textStyle: const TextStyle(
            fontFamily: 'MyKidsNunito',
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(48, 50),
          side: BorderSide(color: outline, width: borderWidth),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(math.min(radius, 18)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: 'MyKidsNunito',
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(math.min(radius, 16)),
          borderSide: BorderSide(color: outline, width: borderWidth),
        ),
        contentPadding: const EdgeInsets.all(16),
        errorMaxLines: 4,
        helperMaxLines: 4,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: soft,
        labelStyle: TextStyle(
          color: ink,
          fontFamily: 'MyKidsNunito',
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(math.min(radius, 15)),
          side: BorderSide(color: outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: muted,
        indicatorColor: accent,
        labelStyle: const TextStyle(
          fontFamily: 'MyKidsNunito',
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: ink,
        iconColor: accent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      ),
      dividerColor: outline,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: soft,
        linearMinHeight: 8,
        borderRadius: BorderRadius.circular(8),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: GamePageTransition(),
          TargetPlatform.windows: GamePageTransition(),
        },
      ),
    );
  }
}

class GamePageTransition extends PageTransitionsBuilder {
  const GamePageTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .025),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

/// A real, semantic control. No text or hit target is baked into an image.
class GameNavigation extends StatelessWidget {
  final int selected;
  final bool showMoney;
  final ValueChanged<int> onSelect;
  const GameNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    this.showMoney = true,
  });
  @override
  Widget build(BuildContext context) {
    final design = gameDesign.value!;
    return ColoredBox(
      color: design.navigation,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 6, 7),
          child: Row(
            children: [
              for (final entry in const {
                0: 'Сегодня',
                1: 'Календарь',
                2: 'Задания',
                3: 'Монеты',
                4: 'Семья',
              }.entries)
                if (showMoney || entry.key != 3)
                  Expanded(
                    child: Semantics(
                      selected: entry.key == selected,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: entry.key == selected
                              ? design.ink
                              : design.onNavigation,
                          backgroundColor: entry.key == selected
                              ? design.reward
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              math.min(design.radius, 16),
                            ),
                          ),
                        ),
                        onPressed: () => onSelect(entry.key),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GameIcon(entry.key, size: 28),
                            const SizedBox(height: 5),
                            Text(
                              entry.value,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cells refer to the unchanged ImageGen sprite atlas. Rendering is shared by
/// preview, screenshot tests and the Android application.
class GameIcon extends StatelessWidget {
  final int index;
  final double size;
  const GameIcon(this.index, {super.key, this.size = 32});

  static const atlasSize = Size(1448, 1086);

  // The ImageGen artwork is not an evenly spaced grid. These rectangles
  // contain each complete subject plus transparent room for its outline.
  static const sources = <Rect>[
    Rect.fromLTRB(18, 67, 371, 391),
    Rect.fromLTRB(391, 43, 707, 385),
    Rect.fromLTRB(749, 41, 1049, 393),
    Rect.fromLTRB(1110, 69, 1430, 392),
    Rect.fromLTRB(21, 409, 391, 750),
    Rect.fromLTRB(402, 428, 713, 744),
    Rect.fromLTRB(709, 454, 1092, 723),
    Rect.fromLTRB(1112, 411, 1441, 747),
    Rect.fromLTRB(20, 770, 361, 1044),
    Rect.fromLTRB(388, 765, 714, 1043),
    Rect.fromLTRB(736, 740, 1068, 1047),
    Rect.fromLTRB(1108, 748, 1429, 1059),
  ];

  @override
  Widget build(BuildContext context) {
    final source = sources[index.clamp(0, sources.length - 1)];
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        // Fit the complete crop into the space actually given by the parent.
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox.fromSize(
            size: source.size,
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    left: -source.left,
                    top: -source.top,
                    width: atlasSize.width,
                    height: atlasSize.height,
                    child: Image.asset(
                      'assets/designs/game-icons.png',
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GameScene extends StatelessWidget {
  final String title, description;
  final bool compact;
  const GameScene({
    super.key,
    required this.title,
    required this.description,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) {
    final design = gameDesign.value!;
    final dark = design.id == 'squad';
    final textColor = dark ? Colors.white : design.ink;
    return LayoutBuilder(
      builder: (context, size) {
        final largeText = MediaQuery.textScalerOf(context).scale(16) > 22;
        if (largeText) {
          return Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2.6,
                  child: Image.asset(design.scene, fit: BoxFit.cover),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 7),
                      Text(description),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        final headingStyle = TextStyle(
          fontFamily: 'MyKidsNunito',
          fontSize: compact ? 23 : 26,
          fontWeight: FontWeight.w900,
          height: 1.08,
          color: textColor,
        );
        final descriptionStyle = TextStyle(
          fontFamily: 'MyKidsNunito',
          fontSize: 13,
          height: 1.3,
          color: textColor,
        );
        final textWidth = math.max(50.0, size.maxWidth * .58 - 28);
        final headingMeasure = TextPainter(
          text: TextSpan(text: title, style: headingStyle),
          textDirection: TextDirection.ltr,
          maxLines: 3,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: textWidth);
        final descriptionMeasure = TextPainter(
          text: TextSpan(text: description, style: descriptionStyle),
          textDirection: TextDirection.ltr,
          maxLines: 4,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: textWidth);
        final height = math.max(
          compact ? 120.0 : 146.0,
          headingMeasure.height + descriptionMeasure.height + 60,
        );
        headingMeasure.dispose();
        descriptionMeasure.dispose();
        return Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 14),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(design.radius),
            border: Border.all(
              color: design.outline,
              width: design.borderWidth,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                design.scene,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -.25),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: size.maxWidth * .58,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      // Keep the complete text column protected from bright
                      // or dark character details; fade only after its ink.
                      stops: const [0, .92, 1],
                      colors: [
                        dark
                            ? const Color(0xee102966)
                            : design.background.withValues(alpha: .97),
                        dark
                            ? const Color(0xee102966)
                            : design.background.withValues(alpha: .97),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 23 : 26,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
