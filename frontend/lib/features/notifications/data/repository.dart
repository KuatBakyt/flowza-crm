import '../../../core/api.dart';
import '../../../core/models.dart';

class NotificationsRepository extends ResourceRepository<NotificationDto> {
  NotificationsRepository(ApiClient api)
    : super(api, 'notifications/', NotificationDto.fromJson);
}
