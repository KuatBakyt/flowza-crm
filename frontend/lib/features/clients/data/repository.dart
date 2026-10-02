import '../../../core/api.dart';
import '../../../core/models.dart';

class ClientsRepository extends ResourceRepository<ClientDto> {
  ClientsRepository(ApiClient api) : super(api, 'clients/', ClientDto.fromJson);
}
