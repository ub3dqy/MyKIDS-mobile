import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'design_review_repository.dart';
import 'design_review_bridge.dart';
import 'design_system.dart';

class ReviewPageSelection extends ValueNotifier<int> {
  ReviewPageSelection() : super(0);
  void select(int page) {
    value = page;
    notifyListeners();
  }
}

/// Local, authenticated Dart VM service control, compiled only into the
/// standalone review entry. It drives mounted production widgets for capture.
class DesignReviewControl {
  static bool registered = false;
  static final errors = <String>[];
  static DesignReviewControl? current;
  final DesignReviewRepository repository;
  final GlobalKey<NavigatorState> navigation;
  final GlobalKey surface;
  final ReviewPageSelection pages;
  final void Function(String) action;
  DesignReviewControl({
    required this.repository,
    required this.navigation,
    required this.surface,
    required this.pages,
    required this.action,
  });

  void bind() {
    installReviewBridge(execute);
    if (kReleaseMode) return;
    current = this;
    if (registered) return;
    registered = true;
    developer.registerExtension('ext.mykids.designReview', (
      _,
      parameters,
    ) async {
      try {
        final control = current;
        if (control == null) throw StateError('Review is closed');
        final result = await control.execute(parameters);
        return developer.ServiceExtensionResponse.result(jsonEncode(result));
      } catch (error) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          error.toString(),
        );
      }
    });
  }

  Future<void> frame() async {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  List<Element> elements() {
    final result = <Element>[];
    void visit(Element element) {
      result.add(element);
      element.visitChildElements(visit);
    }

    surface.currentContext?.visitChildElements(visit);
    return result;
  }

  List<Element> matchingText(String label) => elements()
      .where(
        (e) =>
            e.widget is Text &&
            (e.widget as Text).data == label &&
            ModalRoute.of(e)?.isCurrent != false,
      )
      .toList();

  Future<void> tap(String label) async {
    var matches = matchingText(label);
    if (matches.isEmpty) {
      final scrollable = elements()
          .whereType<StatefulElement>()
          .where(
            (e) =>
                e.state is ScrollableState &&
                ModalRoute.of(e)?.isCurrent != false,
          )
          .map((e) => e.state as ScrollableState)
          .where(
            (s) =>
                s.position.hasContentDimensions &&
                s.position.axis == Axis.vertical &&
                s.position.maxScrollExtent > 0,
          )
          .firstOrNull;
      if (scrollable != null) {
        final position = scrollable.position;
        for (
          var offset = 0.0;
          offset <= position.maxScrollExtent + position.viewportDimension;
          offset += position.viewportDimension * .65
        ) {
          position.jumpTo(offset.clamp(0, position.maxScrollExtent));
          await frame();
          matches = matchingText(label);
          if (matches.isNotEmpty) break;
        }
      }
    }
    if (matches.isEmpty) throw StateError('Visible text not found: $label');
    bool invoked = false;
    matches.last.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ButtonStyleButton && widget.onPressed != null) {
        widget.onPressed!();
        invoked = true;
        return false;
      }
      if (widget is ChoiceChip && widget.onSelected != null) {
        widget.onSelected!(true);
        invoked = true;
        return false;
      }
      if (widget is InkWell && widget.onTap != null) {
        widget.onTap!();
        invoked = true;
        return false;
      }
      return true;
    });
    if (!invoked) throw StateError('No enabled action for $label');
  }

  Future<Map<String, dynamic>> execute(Map<String, String> parameters) async {
    final operation = parameters['op'] ?? 'state';
    if (operation == 'prepare') {
      action('reset');
      repository.switchRole(parameters['id'] ?? 'child');
      pages.select(0);
      errors.clear();
    } else if (operation == 'theme') {
      final design = GameDesign.byId(parameters['id'] ?? '');
      if (design == null) throw StateError('Unknown design');
      gameDesign.value = design;
    } else if (operation == 'role') {
      navigation.currentState!.popUntil((r) => r.isFirst);
      repository.switchRole(parameters['id'] ?? 'child');
    } else if (operation == 'page') {
      navigation.currentState!.popUntil((r) => r.isFirst);
      pages.select(int.parse(parameters['id'] ?? '0').clamp(0, 5));
    } else if (operation == 'action') {
      action(parameters['id'] ?? 'reset');
    } else if (operation == 'back') {
      if (navigation.currentState!.canPop()) navigation.currentState!.pop();
    } else if (operation == 'tap') {
      await tap(parameters['label'] ?? '');
    } else if (operation == 'menu') {
      final menu = elements().whereType<StatefulElement>().firstWhere(
        (e) =>
            e.widget is PopupMenuButton<String> &&
            (e.widget as PopupMenuButton<String>).tooltip ==
                parameters['label'],
      );
      (menu.state as PopupMenuButtonState<String>).showButtonMenu();
    } else if (operation == 'icon') {
      final button = elements()
          .where(
            (e) =>
                e.widget is IconButton && ModalRoute.of(e)?.isCurrent != false,
          )
          .map((e) => e.widget as IconButton)
          .firstWhere(
            (w) => w.tooltip == parameters['label'] && w.onPressed != null,
          );
      button.onPressed!();
    } else if (operation == 'field') {
      final fields = elements()
          .where(
            (e) =>
                e.widget is TextField && ModalRoute.of(e)?.isCurrent != false,
          )
          .map((e) => e.widget as TextField)
          .toList();
      final field = fields[int.parse(parameters['id'] ?? '0')];
      field.controller!.text = parameters['value'] ?? '';
      field.onChanged?.call(parameters['value'] ?? '');
    } else if (operation == 'clearErrors') {
      errors.clear();
    } else if (operation == 'tab') {
      final element = elements()
          .where(
            (e) => e.widget is TabBar && ModalRoute.of(e)?.isCurrent != false,
          )
          .first;
      final tabBar = element.widget as TabBar;
      final controller = tabBar.controller ?? DefaultTabController.of(element);
      controller.animateTo(int.parse(parameters['id'] ?? '0'));
    } else if (operation == 'scroll') {
      final active = elements()
          .where(
            (e) =>
                e is StatefulElement &&
                e.state is ScrollableState &&
                ModalRoute.of(e)?.isCurrent != false,
          )
          .cast<StatefulElement>()
          .toList();
      final state = active
          .map((e) => e.state as ScrollableState)
          .where(
            (s) =>
                s.position.hasContentDimensions &&
                s.position.maxScrollExtent > 0,
          )
          .firstOrNull;
      if (state != null) {
        final fraction = double.parse(parameters['fraction'] ?? '0');
        state.position.jumpTo(
          state.position.maxScrollExtent * fraction.clamp(0, 1),
        );
      }
    } else if (operation != 'state' && operation != 'capture') {
      throw StateError('Unknown operation');
    }
    await frame();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await frame();
    if (operation == 'prepare') {
      // Closing a real dialog can finish its save callback after it pops.
      // Let that callback settle, then remove transient notices from the
      // previous example before presenting the next independent screen.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final context = navigation.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..clearSnackBars()
          ..removeCurrentSnackBar();
      }
      await frame();
    }
    if (operation == 'capture') {
      final boundary =
          surface.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final scale = double.parse(parameters['scale'] ?? '1');
      if (!scale.isFinite || scale <= 0 || scale > 4) {
        throw ArgumentError.value(
          scale,
          'scale',
          'Must be greater than 0 and at most 4',
        );
      }
      final density = View.of(surface.currentContext!).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: density);
      ui.Image? scaled;
      try {
        // Capture the physical rendering first. Exporting the layer directly
        // at 1x changes the engine's device-space shadows on high-density
        // screens, even though text and layout still look correct.
        final width = (boundary.size.width * scale).ceil();
        final height = (boundary.size.height * scale).ceil();
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        try {
          scaled = await picture.toImage(width, height);
        } finally {
          picture.dispose();
        }
        final bytes = await scaled.toByteData(format: ui.ImageByteFormat.png);
        return {
          'png': base64Encode(bytes!.buffer.asUint8List()),
          'width': scaled.width,
          'height': scaled.height,
          'design': gameDesign.value?.id,
        };
      } finally {
        scaled?.dispose();
        image.dispose();
      }
    }
    return {
      'design': gameDesign.value?.id,
      'role': repository.role,
      'page': pages.value,
      'online': repository.online,
      'errors': List<String>.of(errors),
      'balance': repository.snapshot?['balance'],
      'texts': elements()
          .where(
            (e) => e.widget is Text && ModalRoute.of(e)?.isCurrent != false,
          )
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toList(),
    };
  }
}
