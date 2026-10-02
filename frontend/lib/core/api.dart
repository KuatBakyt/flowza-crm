import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'failure.dart';

abstract interface class TokenStore {
  Future<String?> access();
  Future<String?> refresh();
  Future<void> save(String a, String r);
  Future<void> clear();
}

class SecureTokens implements TokenStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> access() => storage.read(key: 'flowza.access');
  @override
  Future<String?> refresh() => storage.read(key: 'flowza.refresh');
  @override
  Future<void> save(String a, String r) async {
    await storage.write(key: 'flowza.refresh', value: r);
    await storage.write(key: 'flowza.access', value: a);
  }

  @override
  Future<void> clear() async {
    await storage.delete(key: 'flowza.access');
    await storage.delete(key: 'flowza.refresh');
  }
}

class ApiClient {
  final Dio dio, public;
  final TokenStore tokens;
  void Function()? onUnauthorized;
  Future<void>? _refreshing;
  ApiClient(this.tokens, {String? baseUrl, HttpClientAdapter? adapter})
    : dio = Dio(
        BaseOptions(
          baseUrl:
              baseUrl ??
              const String.fromEnvironment(
                'API_BASE_URL',
                defaultValue: 'http://localhost:8000/api/v1/',
              ),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
        ),
      ),
      public = Dio(
        BaseOptions(
          baseUrl:
              baseUrl ??
              const String.fromEnvironment(
                'API_BASE_URL',
                defaultValue: 'http://localhost:8000/api/v1/',
              ),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
        ),
      ) {
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      public.httpClientAdapter = adapter;
    }
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          final a = await tokens.access();
          if (a != null) o.headers['Authorization'] = 'Bearer $a';
          h.next(o);
        },
        onError: (e, h) async {
          if (e.response?.statusCode == 401) {
            if (e.requestOptions.extra['retried'] == true) {
              await _clear();
              return h.next(e);
            }
            try {
              await (_refreshing ??= _refresh().whenComplete(
                () => _refreshing = null,
              ));
              e.requestOptions.extra['retried'] = true;
              final response = await dio.fetch<dynamic>(e.requestOptions);
              return h.resolve(response);
            } catch (_) {
              await _clear();
            }
          }
          h.next(e);
        },
      ),
    );
  }
  Future<void> _clear() async {
    await tokens.clear();
    onUnauthorized?.call();
  }

  Future<void> _refresh() async {
    final r = await tokens.refresh();
    if (r == null) {
      throw const AppFailure(code: 'unauthorized', message: 'Войдите снова');
    }
    final j = (await public.post<Json>(
      'auth/refresh/',
      data: {'refresh': r},
    )).data!;
    if (await tokens.refresh() != r) {
      throw const AppFailure(
        code: 'session_changed',
        message: 'Сессия завершена',
      );
    }
    await tokens.save(j['access'] as String, (j['refresh'] ?? r) as String);
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? data,
    Json? query,
  }) async {
    try {
      return (await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
      )).data;
    } on DioException catch (e) {
      throw failure(e);
    }
  }

  static AppFailure failure(DioException e) {
    final j = e.response?.data;
    if (j is Map) {
      return AppFailure(
        code: (j['code'] ?? 'api_error').toString(),
        message: (j['message'] ?? j['detail'] ?? 'Проверьте введённые данные')
            .toString(),
        fields: Map<String, dynamic>.from(
          j['fields'] is Map ? j['fields'] as Map : {},
        ),
      );
    }
    return AppFailure(
      code: 'network',
      message: e.response == null
          ? 'Нет связи с сервером. Проверьте подключение.'
          : 'Ошибка сервера (${e.response?.statusCode})',
    );
  }

  Future<List<T>> all<T>(
    String path,
    T Function(Json) parse, {
    Json? query,
  }) async {
    final out = <T>[];
    var page = 1;
    while (true) {
      final j = await request(path, query: {...?query, 'page': page});
      if (j is List) return j.map((e) => parse(Json.from(e as Map))).toList();
      out.addAll((j['results'] as List).map((e) => parse(Json.from(e as Map))));
      if (j['next'] == null) break;
      page++;
    }
    return out;
  }
}

final tokenProvider = Provider<TokenStore>((ref) => SecureTokens());
final apiProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(tokenProvider)),
);
final liveRevisionProvider = StateProvider<int>((ref) => 0);
final revisionProvider = StateProvider<int>((ref) => 0);
void changed(WidgetRef ref) {
  ref.read(revisionProvider.notifier).state++;
}

class ApiPage<T> {
  final List<T> items;
  final bool hasNext;
  final int page;
  ApiPage(this.items, this.hasNext, this.page);
}

class ResourceRepository<T> {
  final ApiClient api;
  final String path;
  final T Function(Json) parse;
  ResourceRepository(this.api, this.path, this.parse);
  Future<ApiPage<T>> list(Json query, int page) async {
    final j = await api.request(path, query: {...query, 'page': page});
    return ApiPage(
      (j['results'] as List).map((e) => parse(Json.from(e as Map))).toList(),
      j['next'] != null,
      page,
    );
  }

  Future<T> get(String id) async =>
      parse(Json.from(await api.request('$path$id/') as Map));
  Future<T> save(Json data, {String? id}) async => parse(
    Json.from(
      await api.request(
        id == null ? path : '$path$id/',
        method: id == null ? 'POST' : 'PATCH',
        data: data,
      ) as Map,
    ),
  );
}

abstract class PagedNotifier<T> extends AsyncNotifier<ApiPage<T>> {
  int _generation = 0;
  bool _busy = false;
  ResourceRepository<T> repository();
  Json filters();
  @override
  Future<ApiPage<T>> build() {
    ref.watch(revisionProvider);
    ref.listen(liveRevisionProvider, (_, next) => refreshVisible());
    _generation++;
    _busy = false;
    return repository().list(filters(), 1);
  }

  Future<void> refreshVisible() async {
    final old = state.valueOrNull;
    if (old == null || _busy) return;
    _busy = true;
    final generation = _generation;
    try {
      final items = <T>[];
      ApiPage<T>? last;
      for (var page = 1; page <= old.page; page++) {
        last = await repository().list(filters(), page);
        items.addAll(last.items);
        if (!last.hasNext) break;
      }
      if (generation == _generation && last != null) {
        state = AsyncData(ApiPage(items, last.hasNext, last.page));
      }
    } catch (_) {
      // A transient background failure keeps the currently displayed data.
    } finally {
      if (generation == _generation) _busy = false;
    }
  }

  Future<void> more() async {
    final old = state.valueOrNull;
    if (old == null || !old.hasNext || _busy) return;
    _busy = true;
    final generation = _generation;
    try {
      final next = await repository().list(filters(), old.page + 1);
      if (generation == _generation) {
        state = AsyncData(
          ApiPage([...old.items, ...next.items], next.hasNext, next.page),
        );
      }
    } finally {
      if (generation == _generation) _busy = false;
    }
  }
}
