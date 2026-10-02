import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'ui.dart';
import '../features/auth/presentation/auth.dart';
import '../features/auth/presentation/login.dart';
import '../features/dashboard/presentation/dashboard.dart';
import '../features/orders/presentation/orders.dart';
import '../features/orders/presentation/detail.dart';
import '../features/orders/presentation/form.dart';
import '../features/clients/presentation/clients.dart';
import '../features/schedule/presentation/schedule.dart';
import '../features/transfers/presentation/transfers.dart';
import '../features/notifications/presentation/notifications.dart';
import '../features/profile/presentation/profile.dart';

class RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh();
  ref.listen(authProvider, (_, next) => refresh.refresh());
  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (c, s) {
      final auth = ref.read(authProvider);
      final target = s.uri.queryParameters['next'] ?? s.uri.toString();
      if (auth.isLoading || auth.hasError) {
        return s.matchedLocation == '/splash'
            ? null
            : Uri(
                path: '/splash',
                queryParameters: {'next': target},
              ).toString();
      }
      if (auth.valueOrNull == null) {
        return s.matchedLocation == '/login'
            ? null
            : Uri(path: '/login', queryParameters: {'next': target}).toString();
      }
      if (['/login', '/splash'].contains(s.matchedLocation)) {
        final next = s.uri.queryParameters['next'];
        final uri = next == null ? null : Uri.tryParse(next);
        if (uri != null &&
            !uri.hasScheme &&
            !uri.hasAuthority &&
            next!.startsWith('/') &&
            !next.startsWith('//') &&
            !['/login', '/splash'].contains(uri.path)) {
          return next;
        }
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      ShellRoute(
        builder: (c, s, child) => CrmShell(s.uri.path, child),
        routes: [
          GoRoute(path: '/', builder: (c, s) => const DashboardScreen()),
          GoRoute(path: '/orders', builder: (c, s) => const OrdersScreen()),
          GoRoute(
            path: '/orders/new',
            builder: (c, s) => OrderFormScreen(
              client: s.uri.queryParameters['client'],
              start: DateTime.tryParse(s.uri.queryParameters['start'] ?? '')
                  ?.toLocal(),
            ),
          ),
          GoRoute(
            path: '/orders/:id',
            builder: (c, s) => OrderDetailScreen(s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/orders/:id/edit',
            builder: (c, s) => OrderFormScreen(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/orders/:id/transfer',
            builder: (c, s) => OfferScreen(s.pathParameters['id']!),
          ),
          GoRoute(path: '/clients', builder: (c, s) => const ClientsScreen()),
          GoRoute(
            path: '/clients/new',
            builder: (c, s) => const ClientFormScreen(),
          ),
          GoRoute(
            path: '/clients/:id',
            builder: (c, s) => ClientDetailScreen(s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/clients/:id/edit',
            builder: (c, s) => ClientFormScreen(id: s.pathParameters['id']!),
          ),
          GoRoute(path: '/schedule', builder: (c, s) => const ScheduleScreen()),
          GoRoute(
            path: '/schedule/new',
            builder: (c, s) => BlockFormScreen(
              block: s.extra is BlockDto ? s.extra as BlockDto : null,
              start: DateTime.tryParse(s.uri.queryParameters['start'] ?? ''),
            ),
          ),
          GoRoute(
            path: '/transfers',
            builder: (c, s) => const TransfersScreen(),
          ),
          GoRoute(
            path: '/notifications',
            builder: (c, s) => const NotificationsScreen(),
          ),
          GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
          GoRoute(
            path: '/profile/edit',
            builder: (c, s) => const ProfileFormScreen(),
          ),
          GoRoute(
            path: '/statistics',
            builder: (c, s) => const StatisticsScreen(),
          ),
          GoRoute(path: '/more', builder: (c, s) => const MoreScreen()),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: auth.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(auth.error.toString(), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(authProvider),
                        child: const Text('Повторить'),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(authProvider.notifier).logout(),
                        child: const Text('Войти заново'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      ),
    );
  }
}

class CrmShell extends ConsumerWidget {
  final String path;
  final Widget child;
  const CrmShell(this.path, this.child, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final index = path == '/'
        ? 0
        : path.startsWith('/orders')
        ? 1
        : path.startsWith('/schedule')
        ? 3
        : 4;
    const entries = [
      ('Главная', Icons.home_outlined, '/'),
      ('Заказы', Icons.receipt_long_outlined, '/orders'),
      ('Календарь', Icons.calendar_month_outlined, '/schedule'),
      ('Клиенты', Icons.people_outline, '/clients'),
      ('Передачи', Icons.swap_horiz, '/transfers'),
      ('Статистика', Icons.bar_chart, '/statistics'),
      ('Уведомления', Icons.notifications_outlined, '/notifications'),
      ('Профиль', Icons.person_outline, '/profile'),
    ];
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 240,
              child: Material(
                color: Colors.white,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(28),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.layers_rounded,
                              color: blue,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: FittedBox(
                                child: Text(
                                  'Flowza',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          children: [
                            for (final e in entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  selected:
                                      path == e.$3 ||
                                      e.$3 != '/ ' &&
                                          e.$3 != '/' &&
                                          path.startsWith('${e.$3}/'),
                                  selectedTileColor: const Color(0xFFEAF1FF),
                                  selectedColor: blue,
                                  leading: Icon(e.$2),
                                  title: Text(e.$1),
                                  onTap: () => context.go(e.$3),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: FilledButton.icon(
                          onPressed: () => context.push('/orders/new'),
                          icon: const Icon(Icons.add),
                          label: const Text('Новый заказ'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => i == 2
                  ? context.push('/orders/new')
                  : context.go(
                      ['/', '/orders', '/orders/new', '/schedule', '/more'][i],
                    ),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home, color: blue),
                  label: 'Главная',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  label: 'Заказы',
                ),
                NavigationDestination(
                  icon: Icon(Icons.add_circle, color: blue, size: 34),
                  label: 'Добавить',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Календарь',
                ),
                NavigationDestination(icon: Icon(Icons.menu), label: 'Ещё'),
              ],
            ),
    );
  }
}
