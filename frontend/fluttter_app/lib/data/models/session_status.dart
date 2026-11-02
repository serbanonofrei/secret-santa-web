import 'package:json_annotation/json_annotation.dart';

/// `sessions.status` as returned by the Edge Functions.
///
/// Fields of this type are annotated with
/// `@JsonKey(unknownEnumValue: SessionStatus.unknown)`, so a status added on
/// the server later does not break parsing in older app versions.
@JsonEnum()
enum SessionStatus {
  @JsonValue('DRAFT')
  draft,
  @JsonValue('ACTIVE')
  active,
  @JsonValue('CLOSED')
  closed,

  /// Any value this app version does not know.
  unknown,
}
