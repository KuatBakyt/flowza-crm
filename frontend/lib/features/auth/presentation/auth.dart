import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';

final authProvider = AsyncNotifierProvider<AuthNotifier, UserDto?>(
  AuthNotifier.new,
);

class AuthNotifier extends AsyncNotifier<UserDto?> {
  @override
  Future<UserDto?> build() async {
    final api = ref.read(apiProvider);
    api.onUnauthorized = () {
      state = const AsyncData(null);
      ref.read(revisionProvider.notifier).state++;
    };
    if (await api.tokens.access() == null) return null;
    return UserDto.fromJson(Json.from(await api.request('me/') as Map));
  }

  Future<void> login(String identity, String password) async {
    final api = ref.read(apiProvider);
    try {
      final j = (await api.public.post<Json>(
        'auth/login/',
        data: {
          identity.contains('@') ? 'email' : 'phone': identity,
          'password': password,
        },
      )).data!;
      await api.tokens.save(j['access'] as String, j['refresh'] as String);
      ref.read(revisionProvider.notifier).state++;
      state = AsyncData(
        UserDto.fromJson(Json.from(await api.request('me/') as Map)),
      );
    } catch (e) {
      if (e is! Exception) rethrow;
      rethrow;
    }
  }

  Future<void> reload() async {
    state = AsyncData(
      UserDto.fromJson(
        Json.from(await ref.read(apiProvider).request('me/') as Map),
      ),
    );
  }

  Future<void> logout() async {
    final api = ref.read(apiProvider);
    final r = await api.tokens.refresh();
    try {
      if (r != null) {
        await api.request('auth/logout/', method: 'POST', data: {'refresh': r});
      }
    } finally {
      await api.tokens.clear();
      state = const AsyncData(null);
      ref.read(revisionProvider.notifier).state++;
    }
  }
}
