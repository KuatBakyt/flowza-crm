import '../../../core/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/api.dart';
import '../../../core/ui.dart';
import 'auth.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _Login();
}

class _Login extends ConsumerState<LoginScreen> {
  final key = GlobalKey<FormState>();
  final identity = TextEditingController(), password = TextEditingController();
  bool busy = false, hidden = true;
  String? error;
  @override
  void dispose() {
    identity.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!key.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .login(identity.text.trim(), password.text);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is DioException
              ? ApiClient.failure(e).message
              : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LanguageSelector(),
                const SizedBox(height: 16),
                const Icon(Icons.layers_rounded, color: blue, size: 48),
                const SizedBox(height: 20),
                Text(
                  'Flowza',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context, "Заказы, клиенты и расписание —\nв одном месте."),
                  style: TextStyle(
                    color: Color(0xFF78869C),
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Surface(
                  child: Form(
                    key: key,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(context, "Вход в CRM"),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: identity,
                          decoration: InputDecoration(
                            labelText: tr(context, "Телефон или email"),
                          ),
                          autofillHints: const [AutofillHints.username],
                          validator: (s) => s == null || s.trim().isEmpty
                              ? tr(context, "Введите телефон или email")
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: password,
                          obscureText: hidden,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: tr(context, "Пароль"),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => hidden = !hidden),
                              icon: Icon(
                                hidden
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (s) => s == null || s.isEmpty
                              ? tr(context, "Введите пароль")
                              : null,
                          onFieldSubmitted: (_) {
                            if (!busy) submit();
                          },
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: busy ? null : submit,
                          child: Text(
                            busy
                                ? tr(context, "Входим…")
                                : tr(context, "Войти"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  tr(context, "Доступ выдаёт администратор вашей команды."),
                  style: TextStyle(color: Color(0xFF78869C), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
