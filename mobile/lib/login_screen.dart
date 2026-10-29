import 'package:flutter/material.dart';

import 'invitation.dart';
import 'child_visuals.dart';
import 'invitation_scanner.dart';
import 'repository.dart';
import 'visuals.dart';
import 'form_layout.dart';
import 'input_validation.dart';

class LoginScreen extends StatefulWidget {
  final FamilyRepository repository;
  final Future<void> Function() onLogin;
  final Future<void> Function() onUpdates;
  const LoginScreen({
    super.key,
    required this.repository,
    required this.onLogin,
    required this.onUpdates,
  });
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final username = TextEditingController(),
      password = TextEditingController(),
      invite = TextEditingController(),
      name = TextEditingController();
  bool joining = false, busy = false, cancelling = false;
  int loginAttempt = 0;
  String? error;
  final form = GlobalKey<FormState>();
  final fieldErrors = <String, String>{};

  String? check(String key, String? value) {
    if (fieldErrors[key] != null) return fieldErrors[key];
    final text = key == 'password' ? value ?? '' : value?.trim() ?? '';
    if (text.isEmpty) {
      return switch (key) {
        'username' => 'Введите логин',
        'password' => 'Введите пароль',
        'name' => 'Введите имя',
        _ => 'Введите или отсканируйте приглашение',
      };
    }
    if (key == 'username') {
      if (text.length < 3 || text.length > 60) {
        return 'Логин должен содержать от 3 до 60 символов';
      }
      if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(text)) {
        return 'Используйте латинские буквы, цифры, точку, дефис или подчёркивание';
      }
    }
    if (key == 'password') {
      final minimum = joining && widget.repository.variant != 'child' ? 12 : 8;
      if (text.length < minimum) {
        return 'Пароль должен содержать не менее $minimum символов';
      }
      if (text.length > 128) {
        return 'Пароль должен содержать не более 128 символов';
      }
    }
    if (key == 'name' && text.length > 200) {
      return 'Имя должно содержать не более 200 символов';
    }
    return null;
  }

  void edited(String key) {
    if (fieldErrors.remove(key) != null || error != null) {
      setState(() => error = null);
    }
  }

  @override
  void dispose() {
    for (final c in [username, password, invite, name]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget invitationToggle() => TextButton(
    onPressed: busy
        ? null
        : () => setState(() {
            joining = !joining;
            error = null;
            fieldErrors.clear();
          }),
    child: Text(
      joining ? 'У меня уже есть профиль' : 'У меня есть приглашение',
    ),
  );

  Future<void> returnToRoles() async {
    if (cancelling) return;
    if (busy) {
      await cancelConnection(returnToRoleChoice: true);
      return;
    }
    try {
      await widget.repository.selectRole('');
    } catch (_) {
      if (mounted) setState(() => error = 'Не удалось сменить роль');
    }
  }

  Future<void> cancelConnection({bool returnToRoleChoice = false}) async {
    if (!busy || cancelling || widget.repository.snapshot != null) return;
    final attempt = ++loginAttempt;
    setState(() {
      cancelling = true;
      error = null;
    });
    try {
      final cancelled = await widget.repository.cancelLogin();
      if (!mounted || loginAttempt != attempt || !cancelled) return;
      if (returnToRoleChoice) {
        await widget.repository.selectRole('');
      } else if (joining) {
        setState(() {
          joining = false;
          error = 'Профиль мог уже создаться. Войдите с теми же логином и паролем или снова выберите приглашение.';
        });
      }
    } catch (_) {
      if (mounted && loginAttempt == attempt) {
        setState(
          () => error = 'Не удалось отменить подключение. Попробуйте ещё раз',
        );
      }
    } finally {
      if (mounted && loginAttempt == attempt) {
        setState(() {
          busy = false;
          cancelling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) returnToRoles();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: cancelling ? null : returnToRoles),
        title: Text(
          'MyKIDS · ${const {'child': 'Ребёнок', 'parent': 'Родитель', 'relative': 'Родственник'}[widget.repository.variant] ?? ''}',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: form,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: spacedFormItems([
                  const Center(child: FamilyLogo(width: 210)),
                  if (widget.repository.variant == 'child') ...[
                    const Center(child: ChildMotion(size: 170)),
                    const Text(
                      'Твои приключения начинаются здесь!',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const Text('Войдите в свою семью'),
                  if (widget.repository.variant == 'child') invitationToggle(),
                  if (joining) ...[
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final invitation =
                                  await Navigator.push<Invitation>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => InvitationScanner(
                                        role: widget.repository.variant,
                                      ),
                                    ),
                                  );
                              if (!mounted || invitation == null) return;
                              setState(() {
                                invite.text = invitation.token;
                                error = null;
                              });
                            },
                      child: const Text('Сканировать QR-код'),
                    ),
                    LabeledInput(
                      label: 'Приглашение от родителя',
                      child: TextFormField(
                        key: const ValueKey('login-invite'),
                        controller: invite,
                        validator: (value) => check('token', value),
                        onChanged: (_) => edited('token'),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        autocorrect: false,
                      ),
                    ),
                    LabeledInput(
                      label: 'Ваше имя',
                      child: TextFormField(
                        key: const ValueKey('login-name'),
                        controller: name,
                        validator: (value) => check('name', value),
                        onChanged: (_) => edited('name'),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                    ),
                  ],
                  LabeledInput(
                    label: 'Логин',
                    child: TextFormField(
                      key: const ValueKey('login-username'),
                      controller: username,
                      validator: (value) => check('username', value),
                      onChanged: (_) => edited('username'),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      autocorrect: false,
                    ),
                  ),
                  LabeledInput(
                    label: 'Пароль',
                    child: TextFormField(
                      key: const ValueKey('login-password'),
                      controller: password,
                      validator: (value) => check('password', value),
                      onChanged: (_) => edited('password'),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: InputDecoration(
                        helperText:
                            'Не менее ${joining && widget.repository.variant != 'child' ? 12 : 8} символов',
                      ),
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                    ),
                  ),
                  if (error != null) Text(error!),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            fieldErrors.clear();
                            if (!validateAndReveal(form.currentState!)) return;
                            setState(() {
                              busy = true;
                              error = null;
                            });
                            final attempt = ++loginAttempt;
                            try {
                              await widget.repository.login(
                                widget.repository.endpoint,
                                username.text,
                                password.text,
                                invite: joining ? invite.text : null,
                                name: name.text,
                              );
                              if (!mounted || loginAttempt != attempt) return;
                              password.clear();
                              invite.clear();
                              await widget.onLogin();
                            } catch (e) {
                              if (mounted && loginAttempt == attempt) {
                                setState(() {
                                  error = e is ApiFailure
                                      ? e.message
                                      : 'Не удалось связаться с сервером';
                                  if (e is ApiFailure) {
                                    fieldErrors.addAll(e.fields);
                                  }
                                });
                                validateAndReveal(form.currentState!);
                              }
                            } finally {
                              if (mounted && loginAttempt == attempt) {
                                setState(() => busy = false);
                              }
                            }
                          },
                    child: Text(
                      busy
                          ? 'Подключение…'
                          : joining
                          ? 'Присоединиться'
                          : 'Войти',
                    ),
                  ),
                  if (busy)
                    TextButton(
                      onPressed: cancelling ? null : cancelConnection,
                      child: Text(
                        cancelling ? 'Отмена…' : 'Отменить подключение',
                      ),
                    ),
                  if (widget.repository.variant != 'child') invitationToggle(),
                  TextButton(
                    onPressed: busy ? null : widget.onUpdates,
                    child: const Text('Проверить обновления приложения'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
