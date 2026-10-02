// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserDto _$UserDtoFromJson(Map<String, dynamic> json) => UserDto(
  json['id'] as String,
  json['phone'] as String,
  json['role'] as String,
  json['email'] as String?,
  json['master_profile'] == null
      ? null
      : MasterDto.fromJson(json['master_profile'] as Map<String, dynamic>),
);

Map<String, dynamic> _$UserDtoToJson(UserDto instance) => <String, dynamic>{
  'id': instance.id,
  'phone': instance.phone,
  'role': instance.role,
  'email': instance.email,
  'master_profile': instance.profile,
};

MasterDto _$MasterDtoFromJson(Map<String, dynamic> json) => MasterDto(
  json['id'] as String,
  json['full_name'] as String,
  json['city'] as String,
  (json['districts'] as List<dynamic>).map((e) => e as String).toList(),
  json['is_available'] as bool,
  json['internal_rating'] as String,
  (json['completed_orders_count'] as num).toInt(),
  (json['skills'] as List<dynamic>)
      .map((e) => e as Map<String, dynamic>)
      .toList(),
  timezone: json['timezone'] as String? ?? 'Asia/Almaty',
  workingHours: json['working_hours'] as Map<String, dynamic>? ?? {},
);

Map<String, dynamic> _$MasterDtoToJson(MasterDto instance) => <String, dynamic>{
  'id': instance.id,
  'full_name': instance.fullName,
  'city': instance.city,
  'districts': instance.districts,
  'is_available': instance.isAvailable,
  'internal_rating': instance.internalRating,
  'completed_orders_count': instance.completedOrdersCount,
  'skills': instance.skills,
  'timezone': instance.timezone,
  'working_hours': instance.workingHours,
};

ClientDto _$ClientDtoFromJson(Map<String, dynamic> json) => ClientDto(
  json['id'] as String,
  json['phone'] as String,
  json['source'] as String,
  json['notes'] as String,
  json['name'] as String?,
);

Map<String, dynamic> _$ClientDtoToJson(ClientDto instance) => <String, dynamic>{
  'id': instance.id,
  'phone': instance.phone,
  'source': instance.source,
  'notes': instance.notes,
  'name': instance.name,
};

OrderDto _$OrderDtoFromJson(Map<String, dynamic> json) => OrderDto(
  json['id'] as String,
  json['client'] as String,
  json['specialization'] as String,
  json['title'] as String,
  json['description'] as String,
  json['address'] as String,
  json['district'] as String,
  json['status'] as String,
  json['source'] as String,
  json['master'] as String?,
  json['estimated_price'] as String?,
  json['final_price'] as String?,
  DateTime.parse(json['start_at'] as String),
  DateTime.parse(json['end_at'] as String),
  (json['status_history'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ??
      [],
  paidAmount: json['paid_amount'] as String? ?? '0.00',
  outstandingAmount: json['outstanding_amount'] as String?,
);

Map<String, dynamic> _$OrderDtoToJson(OrderDto instance) => <String, dynamic>{
  'id': instance.id,
  'client': instance.client,
  'specialization': instance.specialization,
  'title': instance.title,
  'description': instance.description,
  'address': instance.address,
  'district': instance.district,
  'status': instance.status,
  'source': instance.source,
  'master': instance.master,
  'estimated_price': instance.estimatedPrice,
  'final_price': instance.finalPrice,
  'start_at': instance.startAt.toIso8601String(),
  'end_at': instance.endAt.toIso8601String(),
  'paid_amount': instance.paidAmount,
  'outstanding_amount': instance.outstandingAmount,
  'status_history': instance.statusHistory,
};

BlockDto _$BlockDtoFromJson(Map<String, dynamic> json) => BlockDto(
  json['id'] as String,
  json['master'] as String,
  json['type'] as String,
  json['order'] as String?,
  json['note'] as String?,
  DateTime.parse(json['start_at'] as String),
  DateTime.parse(json['end_at'] as String),
);

Map<String, dynamic> _$BlockDtoToJson(BlockDto instance) => <String, dynamic>{
  'id': instance.id,
  'master': instance.master,
  'type': instance.type,
  'order': instance.order,
  'note': instance.note,
  'start_at': instance.startAt.toIso8601String(),
  'end_at': instance.endAt.toIso8601String(),
};

TransferDto _$TransferDtoFromJson(Map<String, dynamic> json) => TransferDto(
  json['id'] as String,
  json['order'] as String,
  json['from_master'] as String,
  json['to_master'] as String,
  json['status'] as String,
  json['reason'] as String,
  DateTime.parse(json['offered_at'] as String),
  json['order_details'] as Map<String, dynamic>,
);

Map<String, dynamic> _$TransferDtoToJson(TransferDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'order': instance.order,
      'from_master': instance.fromMaster,
      'to_master': instance.toMaster,
      'status': instance.status,
      'reason': instance.reason,
      'offered_at': instance.offeredAt.toIso8601String(),
      'order_details': instance.orderDetails,
    };

NotificationDto _$NotificationDtoFromJson(Map<String, dynamic> json) =>
    NotificationDto(
      json['id'] as String,
      json['title'] as String,
      json['body'] as String,
      json['type'] as String,
      json['is_read'] as bool,
      json['payload'] as Map<String, dynamic>,
      DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$NotificationDtoToJson(NotificationDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'body': instance.body,
      'type': instance.type,
      'is_read': instance.isRead,
      'payload': instance.payload,
      'created_at': instance.createdAt.toIso8601String(),
    };

SummaryDto _$SummaryDtoFromJson(Map<String, dynamic> json) => SummaryDto(
  (json['active'] as num).toInt(),
  (json['completed'] as num).toInt(),
  (json['cancelled'] as num).toInt(),
  (json['transferred'] as num).toInt(),
  (json['new'] as num).toInt(),
  json['revenue'] as String,
);

Map<String, dynamic> _$SummaryDtoToJson(SummaryDto instance) =>
    <String, dynamic>{
      'active': instance.active,
      'completed': instance.completed,
      'cancelled': instance.cancelled,
      'transferred': instance.transferred,
      'new': instance.newOrders,
      'revenue': instance.revenue,
    };
