import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'models.dart';

final clientsCatalog = FutureProvider<List<ClientDto>>((ref) {
  ref.watch(revisionProvider);
  return ref.read(apiProvider).all('clients/', ClientDto.fromJson);
});
final skillsCatalog = FutureProvider<List<Json>>(
  (ref) => ref.read(apiProvider).all('specializations/', (j) => j),
);
final mastersCatalog = FutureProvider<List<MasterDto>>(
  (ref) => ref.read(apiProvider).all('masters/', MasterDto.fromJson),
);
final orderProvider = FutureProvider.family<OrderDto, String>((ref, id) {
  ref.watch(revisionProvider);
  return ResourceRepository(
    ref.read(apiProvider),
    'orders/',
    OrderDto.fromJson,
  ).get(id);
});
final clientProvider = FutureProvider.family<ClientDto, String>((ref, id) {
  ref.watch(revisionProvider);
  return ResourceRepository(
    ref.read(apiProvider),
    'clients/',
    ClientDto.fromJson,
  ).get(id);
});
final summaryPeriod = StateProvider<String>((ref) => 'week');
final summaryProvider = FutureProvider<SummaryDto>((ref) async {
  ref.watch(revisionProvider);
  return SummaryDto.fromJson(
    Json.from(
      await ref
              .read(apiProvider)
              .request(
                'dashboard/summary/',
                query: {'period': ref.watch(summaryPeriod)},
              )
          as Map,
    ),
  );
});
