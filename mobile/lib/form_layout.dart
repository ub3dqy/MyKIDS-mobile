import 'package:flutter/material.dart';

/// Labels stay readable at large text sizes instead of crossing field borders.
class LabeledInput extends StatelessWidget {
  final String label;
  final Widget child;
  const LabeledInput({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
      const SizedBox(height: 8),
      Semantics(label: label, child: child),
    ],
  );
}

List<Widget> spacedFormItems(List<Widget> children, {double gap = 16}) => [
  for (var i = 0; i < children.length; i++) ...[
    if (i > 0) SizedBox(height: gap),
    children[i],
  ],
];
