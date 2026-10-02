import 'package:json_annotation/json_annotation.dart';
part 'models.g.dart';

typedef Json = Map<String, dynamic>;

@JsonSerializable()
class UserDto {
  final String id, phone, role;
  final String? email;
  @JsonKey(name: 'master_profile')
  final MasterDto? profile;
  UserDto(this.id, this.phone, this.role, this.email, this.profile);
  factory UserDto.fromJson(Json j) => _$UserDtoFromJson(j);
  Json toJson() => _$UserDtoToJson(this);
  bool get admin => role == 'ADMIN';
  String get name => profile?.fullName ?? 'Администратор';
}

@JsonSerializable(fieldRename: FieldRename.snake)
class MasterDto {
  final String id, fullName, city;
  final List<String> districts;
  final bool isAvailable;
  final String internalRating;
  final int completedOrdersCount;
  final List<Json> skills;
  @JsonKey(defaultValue: "Asia/Almaty")
  final String timezone;
  @JsonKey(defaultValue: <String, dynamic>{})
  final Json workingHours;
  MasterDto(
    this.id,
    this.fullName,
    this.city,
    this.districts,
    this.isAvailable,
    this.internalRating,
    this.completedOrdersCount,
    this.skills, {
    this.timezone = "Asia/Almaty",
    this.workingHours = const {},
  });
  factory MasterDto.fromJson(Json j) => _$MasterDtoFromJson(j);
  Json toJson() => _$MasterDtoToJson(this);
}

@JsonSerializable()
class ClientDto {
  final String id, phone, source, notes;
  final String? name;
  ClientDto(this.id, this.phone, this.source, this.notes, this.name);
  factory ClientDto.fromJson(Json j) => _$ClientDtoFromJson(j);
  Json toJson() => _$ClientDtoToJson(this);
  String get label => name?.isNotEmpty == true ? name! : phone;
}

@JsonSerializable(fieldRename: FieldRename.snake)
class OrderDto {
  final String id,
      client,
      specialization,
      title,
      description,
      address,
      district,
      status,
      source;
  final String? master, estimatedPrice, finalPrice;
  final DateTime startAt, endAt;
  @JsonKey(defaultValue: "0.00")
  final String paidAmount;
  final String? outstandingAmount;
  @JsonKey(defaultValue: <Json>[])
  final List<Json> statusHistory;
  OrderDto(
    this.id,
    this.client,
    this.specialization,
    this.title,
    this.description,
    this.address,
    this.district,
    this.status,
    this.source,
    this.master,
    this.estimatedPrice,
    this.finalPrice,
    this.startAt,
    this.endAt,
    this.statusHistory, {
    this.paidAmount = "0.00",
    this.outstandingAmount,
  });
  factory OrderDto.fromJson(Json j) => _$OrderDtoFromJson(j);
  Json toJson() => _$OrderDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class BlockDto {
  final String id, master, type;
  final String? order, note;
  final DateTime startAt, endAt;
  BlockDto(
    this.id,
    this.master,
    this.type,
    this.order,
    this.note,
    this.startAt,
    this.endAt,
  );
  factory BlockDto.fromJson(Json j) => _$BlockDtoFromJson(j);
  Json toJson() => _$BlockDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class TransferDto {
  final String id, order, fromMaster, toMaster, status, reason;
  final DateTime offeredAt;
  final Json orderDetails;
  TransferDto(
    this.id,
    this.order,
    this.fromMaster,
    this.toMaster,
    this.status,
    this.reason,
    this.offeredAt,
    this.orderDetails,
  );
  factory TransferDto.fromJson(Json j) => _$TransferDtoFromJson(j);
  Json toJson() => _$TransferDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class NotificationDto {
  final String id, title, body, type;
  final bool isRead;
  final Json payload;
  final DateTime createdAt;
  NotificationDto(
    this.id,
    this.title,
    this.body,
    this.type,
    this.isRead,
    this.payload,
    this.createdAt,
  );
  factory NotificationDto.fromJson(Json j) => _$NotificationDtoFromJson(j);
  Json toJson() => _$NotificationDtoToJson(this);
}

@JsonSerializable()
class SummaryDto {
  final int active, completed, cancelled, transferred;
  @JsonKey(name: 'new')
  final int newOrders;
  final String revenue;
  SummaryDto(
    this.active,
    this.completed,
    this.cancelled,
    this.transferred,
    this.newOrders,
    this.revenue,
  );
  factory SummaryDto.fromJson(Json j) => _$SummaryDtoFromJson(j);
  Json toJson() => _$SummaryDtoToJson(this);
}
