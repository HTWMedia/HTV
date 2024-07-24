//import 'dart:ffi' as pri;

import 'package:fijkplayer_ijkfix/fijkplayer_ijkfix.dart';
import 'package:flutter/material.dart';
import 'package:mobx/mobx.dart';

import '../models/iptv.dart';
import '../utils/logger.dart';
import '../utils/request.dart';

part 'player.g.dart';

class PlayerStore = PlayerStoreBase with _$PlayerStore;

/// 播放状态
enum PlayerState {
  /// 等待播放
  waiting,

  /// 播放中
  playing,

  /// 播放失败
  failed,
}

final _logger = LoggerUtil.create(['播放器']);

abstract class PlayerStoreBase with Store {
  /// 播放器
  @observable
  FijkPlayer player=FijkPlayer();

  /// 宽高比
  @observable
  double? aspectRatio;

  /// 分辨率
  @observable
  Size resolution = Size.zero;

  /// 播放状态
  @observable
  PlayerState state = PlayerState.waiting;

  /// 播放状态
  @observable
  String errorInfo ='';

  /// 播放直播源
  @action
  Future<void> playIptv(Iptv iptv) async {
    try {
      _logger.debug('播放直播源: $iptv');
      state = PlayerState.waiting;

      await player.setOption(FijkOption.hostCategory, "request-screen-on", 1);
      await player.setOption(FijkOption.formatCategory, "dns_cache_clear", 1);
      await player.setOption(FijkOption.playerCategory, "mediacodec", 1);
      await player.setOption(FijkOption.playerCategory, "infbuf", 1);
      await player.setOption(FijkOption.playerCategory, "reconnect", 3);

      player.reset().then((value) {
        //player.enterFullScreen();
        player.setVolume(1.0);
        player.setDataSource(iptv.url,autoPlay: true);
      });

      state = PlayerState.playing;
      aspectRatio = player.value.size?.aspectRatio;
      resolution = player.value.size??Size.zero;
    } catch (e, st) {
      try {
        var result = await RequestUtil.get(
            'http://8.136.199.131/Home/GetIPTV?s=' + iptv.name);
        player.reset().then((value) {
          iptv.url = result;
          player.setDataSource(result, autoPlay: true);
        });

        state = PlayerState.playing;
        aspectRatio = player.value.size?.aspectRatio;
        resolution = player.value.size??Size.zero;
      }
      catch(ie,ist) {
        errorInfo = ie.toString();
        _logger.handle(ie, ist);
        state = PlayerState.failed;
        rethrow;
      }
    }
  }
}
