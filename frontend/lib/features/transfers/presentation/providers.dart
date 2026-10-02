import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';

final transfersFilter = StateProvider<Json>((ref) => {});
final transfersProvider =
    AsyncNotifierProvider<TransfersNotifier, ApiPage<TransferDto>>(
      TransfersNotifier.new,
    );

class TransfersNotifier extends PagedNotifier<TransferDto> {
  @override
  ResourceRepository<TransferDto> repository() => ResourceRepository(
    ref.read(apiProvider),
    ref.watch(transfersFilter)['history'] == true
        ? 'transfers/'
        : 'transfers/incoming/',
    TransferDto.fromJson,
  );
  @override
  Json filters() => {};
}
