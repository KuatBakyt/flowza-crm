import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';
import '../data/repository.dart';

final ordersFilter = StateProvider<Json>((ref) => {});
final ordersProvider = AsyncNotifierProvider<OrdersNotifier, ApiPage<OrderDto>>(
  OrdersNotifier.new,
);

class OrdersNotifier extends PagedNotifier<OrderDto> {
  @override
  ResourceRepository<OrderDto> repository() =>
      OrdersRepository(ref.read(apiProvider));
  @override
  Json filters() => ref.watch(ordersFilter);
}
