import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'form_layout.dart';
import 'family_action.dart';
import 'input_validation.dart';
import 'repository.dart';
import 'task_rewards.dart';

class FamilyField {
  final String key;
  final String label;
  final String kind;
  final bool required;
  final Map<String, String> choices;
  final dynamic initial;
  final String? Function(dynamic)? validator;
  final bool Function(Map<String, dynamic>)? visibleWhen;
  final String? help;
  const FamilyField(
    this.key,
    this.label, {
    this.kind = 'text',
    this.required = true,
    this.choices = const {},
    this.initial,
    this.validator,
    this.visibleWhen,
    this.help,
  });
}

Future<Map<String, dynamic>?> familyForm(
  BuildContext context,
  String title,
  List<FamilyField> fields, {
  Object? Function(Map<String, dynamic>)? validate,
  Future<dynamic> Function(Map<String, dynamic>)? onSave,
  FamilyActionAccess? access,
  bool offlineSave = false,
}) async {
  final route = MaterialPageRoute<Map<String, dynamic>>(
    builder: (_) => FamilyForm(
      title: title,
      fields: fields,
      validate: validate,
      onSave: onSave,
      access: access,
      offlineSave: offlineSave,
    ),
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;
  return result;
}

class FamilyForm extends StatefulWidget {
  final String title;
  final List<FamilyField> fields;
  final Object? Function(Map<String, dynamic>)? validate;
  final Future<dynamic> Function(Map<String, dynamic>)? onSave;
  final FamilyActionAccess? access;
  final bool offlineSave;
  const FamilyForm({
    super.key,
    required this.title,
    required this.fields,
    this.validate,
    this.onSave,
    this.access,
    this.offlineSave = false,
  });
  @override
  State<FamilyForm> createState() => _FamilyFormState();
}

class _FamilyFormState extends State<FamilyForm> {
  final formKey = GlobalKey<FormState>();
  final actionAnchor = GlobalKey();
  final values = <String, dynamic>{};
  final controllers = <String, TextEditingController>{};
  final anchors = <String, GlobalKey>{};
  final errors = <String, String>{};
  String? saveError;
  bool saving = false;
  bool completed = false;
  bool accessReplaced = false;
  bool closing = false;
  String? queuedMessage;
  Map<String, dynamic>? submittedData;

  bool get permitted => !accessReplaced && (widget.access?.valid ?? true);
  bool get connected =>
      widget.offlineSave || (widget.access?.repository.online ?? true);

  void accessChanged() {
    if (!mounted) return;
    if (!permitted) FocusScope.of(context).unfocus();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.access?.repository.addListener(accessChanged);
    widget.access?.addListener(accessChanged);
    for (final field in widget.fields) {
      anchors[field.key] = GlobalKey();
      values[field.key] =
          field.initial ??
          (field.kind == 'bool'
              ? false
              : field.kind == 'weekdays'
              ? <int>[]
              : null);
      if (['text', 'note', 'int', 'signed'].contains(field.kind)) {
        controllers[field.key] = TextEditingController(
          text: field.initial?.toString() ?? (field.kind == 'int' ? '0' : ''),
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant FamilyForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.access, widget.access)) {
      accessReplaced = true;
      oldWidget.access?.repository.removeListener(accessChanged);
      oldWidget.access?.removeListener(accessChanged);
      widget.access?.repository.addListener(accessChanged);
      widget.access?.addListener(accessChanged);
      FocusScope.of(context).unfocus();
    }
  }

  void reveal(String field) {
    final context = anchors[field]?.currentContext;
    if (context != null) revealInvalidField(context);
  }

  void closeSaved() {
    if (!mounted ||
        closing ||
        !permitted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() => closing = true);
    Navigator.pop(context, submittedData);
  }

  void queued(Map<String, dynamic> data) {
    completed = true;
    submittedData = data;
    queuedMessage = 'Запрос сохранён на устройстве. После подключения проверим результат. Повторно отправлять его не нужно.';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !permitted || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final target = actionAnchor.currentContext;
      if (target != null) {
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: 1,
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 180),
          ),
        );
      }
    });
  }

  Future<void> save() async {
    if (saving ||
        completed ||
        !permitted ||
        !connected ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      errors.clear();
      saveError = null;
    });
    if (!validateAndReveal(formKey.currentState!)) return;
    final data = <String, dynamic>{};
    for (final field in widget.fields) {
      if (field.visibleWhen?.call(values) == false) continue;
      dynamic value = values[field.key];
      if (controllers.containsKey(field.key)) {
        final text = controllers[field.key]!.text.trim();
        value = ['int', 'signed'].contains(field.kind)
            ? int.tryParse(text)
            : text;
      }
      if (field.required &&
          (value == null ||
              (value is String && value.isEmpty) ||
              (value is List && value.isEmpty))) {
        setState(() => errors[field.key] = 'Заполните поле «${field.label}»');
        reveal(field.key);
        return;
      }
      if (value != null &&
          !(value is String && value.isEmpty && !field.required)) {
        data[field.key] = value;
      }
      final issue = field.validator?.call(value);
      if (issue != null) {
        setState(() => errors[field.key] = issue);
        formKey.currentState!.validate();
        reveal(field.key);
        return;
      }
    }
    final issue = widget.validate?.call(data);
    if (issue != null) {
      final field = issue is FieldIssue
          ? issue.field
          : widget.fields
                .firstWhere(
                  (field) => issue.toString().toLowerCase().contains(
                    field.label.toLowerCase(),
                  ),
                  orElse: () => widget.fields.first,
                )
                .key;
      setState(
        () => errors[field] = issue is FieldIssue
            ? issue.message
            : issue.toString(),
      );
      formKey.currentState!.validate();
      reveal(field);
      return;
    }
    setState(() => saving = true);
    try {
      final result = await widget.onSave?.call(data);
      if (result is Map && result['queued'] == true) {
        if (mounted) setState(() => queued(data));
        return;
      }
      completed = true;
      submittedData = data;
      if (mounted && permitted && ModalRoute.of(context)?.isCurrent != false) {
        closeSaved();
      }
    } catch (failure) {
      if (!mounted || !permitted) return;
      if (failure is QueuedCommandFailure) {
        setState(() => queued(data));
        return;
      }
      setState(() {
        saveError = failure is ApiFailure
            ? failure.message
            : 'Не удалось связаться с сервером. Попробуйте ещё раз';
        if (failure is ApiFailure) {
          for (final entry in failure.fields.entries) {
            final parts = entry.key.split('.');
            final key = anchors.containsKey(parts.first)
                ? parts.first
                : parts.last;
            errors.putIfAbsent(key, () => entry.value);
          }
        }
      });
      formKey.currentState?.validate();
      final first = widget.fields
          .where((field) => errors.containsKey(field.key))
          .firstOrNull;
      if (first != null) reveal(first.key);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    widget.access?.repository.removeListener(accessChanged);
    widget.access?.removeListener(accessChanged);
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> chooseDate(FamilyField field) async {
    final current = values[field.key] is DateTime
        ? values[field.key] as DateTime
        : DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    if (field.kind == 'datetime') {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(current),
      );
      if (time == null || !mounted) return;
      setState(
        () => values[field.key] = current is tz.TZDateTime
            ? tz.TZDateTime(
                current.location,
                day.year,
                day.month,
                day.day,
                time.hour,
                time.minute,
              )
            : DateTime(day.year, day.month, day.day, time.hour, time.minute),
      );
    } else {
      setState(() => values[field.key] = day);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      top: false,
      child: !permitted
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Семейный доступ изменился. Закройте форму и откройте её заново.',
              ),
            )
          : Form(
              key: formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final field in widget.fields)
                      if (field.visibleWhen?.call(values) != false)
                        Padding(
                          key: anchors[field.key],
                          padding: const EdgeInsets.only(bottom: 18),
                          child: ExcludeFocus(
                            excluding: saving || completed,
                            child: AbsorbPointer(
                              absorbing: saving || completed,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  buildField(field),
                                  if (field.help != null) Text(field.help!),
                                  if (errors[field.key] != null &&
                                      !controllers.containsKey(field.key) &&
                                      field.kind != 'choice')
                                    Text(
                                      errors[field.key]!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    if (!connected && !completed)
                      const Text(
                        'Нет связи с сервером. Введённые данные сохранены в этой форме. Сохранение станет доступно после подключения.',
                      ),
                    if (saveError != null)
                      Text(
                        saveError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (completed) Text(queuedMessage ?? 'Изменения сохранены'),
                    FilledButton(
                      key: actionAnchor,
                      onPressed: completed
                          ? (closing ? null : closeSaved)
                          : saving || !connected
                          ? null
                          : save,
                      child: Text(
                        completed
                            ? 'Закрыть'
                            : saving
                            ? 'Сохранение…'
                            : 'Сохранить',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );

  Widget buildField(FamilyField field) {
    final value = values[field.key];
    if (field.kind == 'task_rewards') {
      return FormField<Map<String, dynamic>>(
        initialValue: Map<String, dynamic>.from(value as Map),
        validator: (_) =>
            errors[field.key] ?? rewardOptionsError(values[field.key]),
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              field.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TaskRewardEditor(
              initial: Map<String, dynamic>.from(value),
              onChanged: (options) {
                values[field.key] = options;
                errors.remove(field.key);
                state.didChange(options);
              },
            ),
            if (state.errorText != null)
              Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    if (field.kind == 'bool') {
      return SwitchListTile(
        title: Text(field.label),
        value: value == true,
        onChanged: (value) => setState(() => values[field.key] = value),
      );
    }
    if (field.kind == 'choice') {
      return LabeledInput(
        label: field.label,
        child: DropdownButtonFormField<String>(
          key: ValueKey('field-${field.key}'),
          initialValue: value as String?,
          isExpanded: true,
          isDense: false,
          itemHeight: null,
          decoration: const InputDecoration(),
          items: field.choices.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (value) => setState(() {
            values[field.key] = value;
            errors.remove(field.key);
          }),
          validator: (value) =>
              errors[field.key] ??
              (field.required && value == null
                  ? 'Выберите: ${field.label}'
                  : null),
        ),
      );
    }
    if (field.kind == 'weekdays') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 1; i <= 7; i++)
                FilterChip(
                  label: Text(
                    const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][i - 1],
                  ),
                  selected: (value as List).contains(i),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      value.add(i);
                    } else {
                      value.remove(i);
                    }
                  }),
                ),
            ],
          ),
        ],
      );
    }
    if (['date', 'datetime', 'time'].contains(field.kind)) {
      return OutlinedButton(
        onPressed: () async {
          if (field.kind == 'time') {
            final time = await showTimePicker(
              context: context,
              initialTime: value is TimeOfDay
                  ? value
                  : const TimeOfDay(hour: 9, minute: 0),
            );
            if (time != null && mounted) {
              setState(() => values[field.key] = time);
            }
          } else {
            await chooseDate(field);
          }
        },
        child: Text(
          '${field.label}: ${value is DateTime
              ? '${value.day}.${value.month}.${value.year}${field.kind == 'datetime' ? ' ${TimeOfDay.fromDateTime(value).format(context)}' : ''}'
              : value is TimeOfDay
              ? value.format(context)
              : 'выбрать'}',
        ),
      );
    }
    return LabeledInput(
      label: field.label,
      child: TextFormField(
        key: ValueKey('field-${field.key}'),
        controller: controllers[field.key],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        onChanged: (_) {
          if (errors.remove(field.key) != null) setState(() {});
        },
        decoration: const InputDecoration(),
        maxLength: field.kind == 'note' ? 4000 : 200,
        minLines: field.kind == 'note' ? 2 : 1,
        maxLines: field.kind == 'note' ? 5 : 1,
        keyboardType: ['int', 'signed'].contains(field.kind)
            ? TextInputType.numberWithOptions(signed: field.kind == 'signed')
            : TextInputType.text,
        validator: (value) {
          if (errors[field.key] != null) return errors[field.key];
          if (field.required && (value == null || value.trim().isEmpty)) {
            return 'Заполните поле «${field.label}»';
          }
          if (['int', 'signed'].contains(field.kind) &&
              value != null &&
              value.isNotEmpty) {
            final number = int.tryParse(value);
            if (number == null ||
                number.abs() > 1000000 ||
                (field.kind == 'int' && number < 0)) {
              return number == null
                  ? 'Введите целое число'
                  : number.abs() > 1000000
                  ? 'Значение должно быть от ${field.kind == 'signed' ? '−1 000 000' : '0'} до 1 000 000'
                  : 'Значение не может быть отрицательным';
            }
          }
          return null;
        },
      ),
    );
  }
}
