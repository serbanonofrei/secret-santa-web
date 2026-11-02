import 'package:freezed_annotation/freezed_annotation.dart';

part 'color_info.freezed.dart';
part 'color_info.g.dart';

/// `{ name, hexColor }`: `myColor` / `giftColor` in join-session,
/// get-my-assignment and recover-assignment responses.
@freezed
class ColorInfo with _$ColorInfo {
  const factory ColorInfo({
    required String name,
    required String hexColor,
  }) = _ColorInfo;

  factory ColorInfo.fromJson(Map<String, dynamic> json) => _$ColorInfoFromJson(json);
}

/// list-colors entry: `{ id, name, hexColor }`.
@freezed
class CatalogColor with _$CatalogColor {
  const factory CatalogColor({
    required int id,
    required String name,
    required String hexColor,
  }) = _CatalogColor;

  factory CatalogColor.fromJson(Map<String, dynamic> json) => _$CatalogColorFromJson(json);
}

/// create-session `selectedColors` entry: `{ catalogId, name, hexColor }`.
@freezed
class SelectedColor with _$SelectedColor {
  const factory SelectedColor({
    required int catalogId,
    required String name,
    required String hexColor,
  }) = _SelectedColor;

  factory SelectedColor.fromJson(Map<String, dynamic> json) => _$SelectedColorFromJson(json);
}
