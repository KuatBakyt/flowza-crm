import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'translations.dart';

abstract interface class LanguageStore {
  Future<String?> read();
  Future<void> write(String language);
}

class SecureLanguageStore implements LanguageStore {
  const SecureLanguageStore();
  static const storage = FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: 'flowza.language');
  @override
  Future<void> write(String language) =>
      storage.write(key: 'flowza.language', value: language);
}

const navigationOrdersLabels = {
  'ru': 'Заказы',
  'kk': 'Тапсырыс',
  'en': 'Orders',
};

const languageNames = {'ru': 'Русский', 'kk': 'Қазақша', 'en': 'English'};
final languageStoreProvider = Provider<LanguageStore>(
  (ref) => const SecureLanguageStore(),
);
final initialLanguageProvider = Provider<String>((ref) => 'ru');
final languageProvider = StateNotifierProvider<LanguageController, String>(
  (ref) => LanguageController(
    ref.read(languageStoreProvider),
    ref.read(initialLanguageProvider),
  ),
);

class LanguageController extends StateNotifier<String> {
  final LanguageStore store;
  LanguageController(this.store, String initial)
    : super(languageNames.containsKey(initial) ? initial : 'ru');
  Future<void> select(String language) async {
    if (!languageNames.containsKey(language)) return;
    await store.write(language);
    state = language;
  }
}

String translate(
  String language,
  String text, [
  List<Object?> values = const [],
]) {
  var result = language == 'ru' ? text : translations[text]?[language] ?? text;
  for (var index = 0; index < values.length; index++) {
    result = result.replaceAll('{$index}', values[index]?.toString() ?? '');
  }
  return result;
}

String tr(
  BuildContext context,
  String text, [
  List<Object?> values = const [],
]) => translate(Localizations.localeOf(context).languageCode, text, values);

class LanguageSelector extends ConsumerStatefulWidget {
  const LanguageSelector({super.key});
  @override
  ConsumerState<LanguageSelector> createState() => _LanguageSelector();
}

class _LanguageSelector extends ConsumerState<LanguageSelector> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey(ref.watch(languageProvider)),
    initialValue: ref.watch(languageProvider),
    decoration: InputDecoration(labelText: tr(context, 'Язык интерфейса')),
    items: [
      for (final entry in languageNames.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: busy
        ? null
        : (value) async {
            if (value == null) return;
            setState(() => busy = true);
            try {
              await ref.read(languageProvider.notifier).select(value);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr(context, 'Не удалось сохранить язык')),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
  );
}
