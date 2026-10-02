import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/models.dart';
import '../data/repository.dart';

final notificationsFilter = StateProvider<Json>((ref) => {});
final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, ApiPage<NotificationDto>>(
      NotificationsNotifier.new,
    );

class NotificationsNotifier extends PagedNotifier<NotificationDto> {
  @override
  ResourceRepository<NotificationDto> repository() =>
      NotificationsRepository(ref.read(apiProvider));
  @override
  Json filters() => ref.watch(notificationsFilter);
}
