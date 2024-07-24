import 'package:json_annotation/json_annotation.dart';

part 'epg.g.dart';

@JsonSerializable()
class Epg {
  /// 频道名称
  late final String channel;

  /// 节目列表
  late final List<EpgProgramme> programmes;

  Epg({
    required this.channel,
    required this.programmes,
  });

  factory Epg.fromJson(Map<String, dynamic> json) => _$EpgFromJson(json);
  Map<String, dynamic> toJson() => _$EpgToJson(this);
}

@JsonSerializable()
class EpgProgramme {
  /// 开始时间
  late final int start;

  /// 结束时间
  late final int stop;

  /// 节目名称
  late final String title;

  EpgProgramme({
    required this.start,
    required this.stop,
    required this.title,
  });

  factory EpgProgramme.fromJson(Map<String, dynamic> json) => _$EpgProgrammeFromJson(json);
  Map<String, dynamic> toJson() => _$EpgProgrammeToJson(this);
}
