import '../../../core/api.dart';
import '../../../core/models.dart';

class TransfersRepository extends ResourceRepository<TransferDto> {
  TransfersRepository(ApiClient api)
    : super(api, 'transfers/incoming/', TransferDto.fromJson);
}
