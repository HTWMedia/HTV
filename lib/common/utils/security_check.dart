import 'dart:io';
import 'package:flutter/services.dart';

class SecurityCheck {
  static const _channel = MethodChannel('com.htwmedia.htv/security');

  /// 检查设备是否已 Root
  static Future<bool> isRooted() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isRooted');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 检查是否为模拟器（简单检测）
  static Future<bool> isEmulator() async {
    if (!Platform.isAndroid) return false;

    try {
      // 通过 Android 属性检测
      final result = await _channel.invokeMethod<bool>('isEmulator');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
