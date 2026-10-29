import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykids_family/call_view.dart';
import 'package:mykids_family/design_system.dart';
import 'package:mykids_family/messenger_widgets.dart';

void main() {
  for (final design in GameDesign.all) {
    for (final ownedRoute in [false, true]) {
      testWidgets(
        '${design.id}: open call menu follows connection; owned=$ownedRoute',
        (tester) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          gameDesign.value = design;
          final state = ValueNotifier<int>(0);
          final navigator = GlobalKey<NavigatorState>();
          var invoked = -1;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            state.dispose();
            gameDesign.value = null;
          });
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: ValueListenableBuilder<int>(
                valueListenable: state,
                builder: (context, generation, _) => FamilyCallView(
                  title: 'Мама',
                  status: generation == 0
                      ? 'Подключение…'
                      : 'Соединение установлено',
                  people: const [CallPerson(name: 'Мама')],
                  onClose: () {},
                  openControls: ownedRoute
                      ? (builder) => navigator.currentState!.push<void>(
                          ModalBottomSheetRoute<void>(
                            builder: builder,
                            isScrollControlled: false,
                          ),
                        )
                      : null,
                  controls: [
                    const CallControl(label: 'Микрофон', icon: Icons.mic),
                    const CallControl(label: 'Камера', icon: Icons.videocam),
                    CallControl(
                      label: 'Динамик',
                      icon: generation == 2
                          ? Icons.volume_up
                          : Icons.volume_down,
                      selected: generation == 2,
                      onPressed: generation == 0 || generation == 3
                          ? null
                          : () => invoked = generation,
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Ещё'));
          await tester.pumpAndSettle();
          final speaker = find.byWidgetPredicate(
            (w) => w is CallControl && w.label == 'Динамик',
          );
          expect(tester.widget<CallControl>(speaker).onPressed, isNull);
          state.value = 1;
          await tester.pumpAndSettle();
          expect(
            tester.widget<CallControl>(speaker).onPressed,
            isNotNull,
            reason:
                'The already-open menu must enable when connection finishes',
          );
          state.value = 2;
          await tester.pumpAndSettle();
          expect(tester.widget<CallControl>(speaker).selected, isTrue);
          expect(tester.widget<CallControl>(speaker).icon, Icons.volume_up);
          state.value = 3;
          await tester.pumpAndSettle();
          expect(
            tester.widget<CallControl>(speaker).onPressed,
            isNull,
            reason: 'Reconnection must disable stale media actions in the open menu',
          );
          state.value = 4;
          await tester.pumpAndSettle();
          await tester.tap(find.text('Динамик'));
          await tester.pumpAndSettle();
          expect(
            invoked,
            4,
            reason: 'The action must belong to the latest call state',
          );
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
