import '../../../core/api.dart';
import '../../../core/models.dart';

class OrdersRepository extends ResourceRepository<OrderDto> {
  OrdersRepository(ApiClient api) : super(api, 'orders/', OrderDto.fromJson);
}
