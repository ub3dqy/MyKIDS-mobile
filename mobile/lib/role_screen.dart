import 'package:flutter/material.dart';

import 'repository.dart';
import 'visuals.dart';

class RoleScreen extends StatefulWidget {
  final FamilyRepository repository;
  const RoleScreen({super.key, required this.repository});

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  bool busy = false;
  String? error;

  Future<void> choose(String role) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.selectRole(role);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Не удалось сохранить выбор. Попробуйте ещё раз',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MyKIDS')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Center(child: FamilyLogo(width: 210)),
            const SizedBox(height: 32),
            Text(
              'Кто будет пользоваться приложением?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Выберите свою роль в семье. Затем войдите в профиль или используйте приглашение от родителя.',
            ),
            const SizedBox(height: 24),
            for (final entry in const [
              (
                'child',
                'Ребёнок',
                'Задания, награды и общение с семьёй',
                Icons.child_care_rounded,
              ),
              (
                'parent',
                'Родитель',
                'Семейные дела и забота о ребёнке',
                Icons.family_restroom_rounded,
              ),
              (
                'relative',
                'Бабушка или дедушка',
                'Общение и участие в жизни семьи',
                Icons.favorite_outline_rounded,
              ),
            ]) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: ValueKey('setup-${entry.$1}'),
                  enabled: !busy,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  leading: Icon(entry.$4),
                  title: Text(entry.$2),
                  subtitle: Text(entry.$3),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: busy ? null : () => choose(entry.$1),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (busy) const Center(child: CircularProgressIndicator()),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
  );
}
