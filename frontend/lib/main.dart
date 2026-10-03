import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/l10n.dart';

import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/live_refresh.dart';
import 'core/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait(['ru', 'kk', 'en'].map(initializeDateFormatting));
  String language = 'ru';
  try {
    language = await const SecureLanguageStore().read() ?? 'ru';
  } catch (_) {}
  runApp(
    ProviderScope(
      overrides: [initialLanguageProvider.overrideWithValue(language)],
      child: const FlowzaApp(),
    ),
  );
}

class FlowzaApp extends ConsumerWidget {
  const FlowzaApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    Intl.defaultLocale = language;
    return MaterialApp.router(
      title: 'Flowza CRM',
      debugShowCheckedModeBanner: false,
      theme: crmTheme(),
      locale: Locale(language),
      supportedLocales: const [Locale('ru'), Locale('kk'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          LiveRefresh(child: child ?? const SizedBox.shrink()),
    );
  }
}
