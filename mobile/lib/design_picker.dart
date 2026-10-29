import 'package:flutter/material.dart';

import 'design_preferences.dart';
import 'design_system.dart';

class DesignSettingsTile extends StatelessWidget {
  final DesignPreferences preferences;
  const DesignSettingsTile({super.key, required this.preferences});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<GameDesign?>(
    valueListenable: gameDesign,
    builder: (context, design, _) => Card(
      child: ListTile(
        key: const ValueKey('appearance-settings'),
        leading: const GameIcon(10, size: 34),
        title: const Text('Оформление'),
        subtitle: Text((design ?? preferences.defaultDesign).name),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => DesignPicker(preferences: preferences),
          ),
        ),
      ),
    ),
  );
}

class DesignPicker extends StatefulWidget {
  final DesignPreferences preferences;
  const DesignPicker({super.key, required this.preferences});

  @override
  State<DesignPicker> createState() => _DesignPickerState();
}

class _DesignPickerState extends State<DesignPicker> {
  String? saving;
  String? error;

  Future<void> select(GameDesign design) async {
    if (saving != null) return;
    setState(() {
      saving = design.id;
      error = null;
    });
    try {
      await widget.preferences.select(design);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Не удалось запомнить выбор. Попробуй ещё раз.');
      }
    } finally {
      if (mounted) setState(() => saving = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Выбери свой мир')),
    body: ValueListenableBuilder<GameDesign?>(
      valueListenable: gameDesign,
      builder: (context, selected, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Все разделы будут в этом стиле.'),
          const SizedBox(height: 8),
          Text(
            'Сейчас: ${(selected ?? widget.preferences.defaultDesign).name}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          const SizedBox(height: 16),
          for (final design in GameDesign.all)
            Semantics(
              selected: design.id == selected?.id,
              child: Card(
                color: design.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(design.radius),
                  side: BorderSide(
                    color: design.id == selected?.id
                        ? design.accent
                        : design.outline,
                    width: design.id == selected?.id ? 3 : design.borderWidth,
                  ),
                ),
                child: InkWell(
                  key: ValueKey('design-option-${design.id}'),
                  onTap: saving == null ? () => select(design) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 2.6,
                        child: Image.asset(
                          design.scene,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    design.name,
                                    style: TextStyle(
                                      color: design.ink,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    design.description,
                                    style: TextStyle(color: design.ink),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (saving == design.id)
                              SizedBox.square(
                                dimension: 26,
                                child: CircularProgressIndicator(
                                  color: design.accent,
                                  strokeWidth: 3,
                                  semanticsLabel: 'Сохраняем оформление',
                                ),
                              )
                            else
                              Icon(
                                design.id == selected?.id
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: design.accent,
                                size: 28,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Text('Выбор сохраняется на этом телефоне.'),
        ],
      ),
    ),
  );
}
