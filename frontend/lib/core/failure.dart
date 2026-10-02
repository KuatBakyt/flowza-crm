import 'package:freezed_annotation/freezed_annotation.dart';
part 'failure.freezed.dart';

@freezed
abstract class AppFailure with _$AppFailure implements Exception {
  const AppFailure._();
  const factory AppFailure({
    required String code,
    required String message,
    @Default(<String, dynamic>{}) Map<String, dynamic> fields,
  }) = _AppFailure;
  @override
  String toString() => message;
}
