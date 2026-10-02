import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';
import '../data/repository.dart';

final clientsFilter = StateProvider<Json>((ref) => {});
final clientsProvider =
    AsyncNotifierProvider<ClientsNotifier, ApiPage<ClientDto>>(
      ClientsNotifier.new,
    );

class ClientsNotifier extends PagedNotifier<ClientDto> {
  @override
  ResourceRepository<ClientDto> repository() =>
      ClientsRepository(ref.read(apiProvider));
  @override
  Json filters() => ref.watch(clientsFilter);
}
