import '../utils/prefs.dart';

/// 调试设置
enum DebugSetting {
  /// 延时渲染
  delayRender,
}

/// 调试设置
class DebugSettings {
  DebugSettings._();

  static bool get delayRender => PrefsUtil.getBool(DebugSetting.delayRender.toString()) ?? false;
  static set delayRender(bool value) => PrefsUtil.setBool(DebugSetting.delayRender.toString(), value);
}