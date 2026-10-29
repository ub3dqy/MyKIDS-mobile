import 'package:flutter/material.dart';

class FieldIssue {
  final String field, message;
  const FieldIssue(this.field, this.message);
}

void revealInvalidField(BuildContext context) {
  if (!context.mounted) return;
  FocusNode? editable, selectable;
  void visit(Element element) {
    if (element.widget case EditableText(:final focusNode)) {
      editable ??= focusNode;
    } else {
      if (element.widget case Focus(:final focusNode)) {
        if (focusNode?.canRequestFocus == true) selectable ??= focusNode;
      }
      element.visitChildren(visit);
    }
  }

  (context as Element).visitChildren(visit);
  (editable ?? selectable)?.requestFocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) {
      Scrollable.ensureVisible(
        context,
        alignment: .15,
        duration: const Duration(milliseconds: 220),
      );
    }
  });
}

bool validateAndReveal(FormState form) {
  final invalid = form.validateGranularly();
  if (invalid.isEmpty) return true;
  revealInvalidField(invalid.first.context);
  return false;
}

void revealNamedField(BuildContext root, String name) {
  Element? found;
  void visit(Element element) {
    if (element.widget.key == ValueKey(name)) {
      found = element;
    }
    if (found == null) element.visitChildren(visit);
  }

  visit(root as Element);
  if (found != null) revealInvalidField(found!);
}
