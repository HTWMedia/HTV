// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'epg.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Epg _$EpgFromJson(Map<String, dynamic> json) => Epg(
      channel: json['channel'] as String,
      programmes: (json['programmes'] as List<dynamic>)
          .map((e) => EpgProgramme.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$EpgToJson(Epg instance) => <String, dynamic>{
      'channel': instance.channel,
      'programmes': instance.programmes,
    };

EpgProgramme _$EpgProgrammeFromJson(Map<String, dynamic> json) => EpgProgramme(
      start: json['start'] as int,
      stop: json['stop'] as int,
      title: json['title'] as String,
    );

Map<String, dynamic> _$EpgProgrammeToJson(EpgProgramme instance) =>
    <String, dynamic>{
      'start': instance.start,
      'stop': instance.stop,
      'title': instance.title,
    };
