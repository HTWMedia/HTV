import 'package:video_player_example/common/index.dart';

/// 应用设置
enum AppSetting {
  /// 开机自启
  bootLaunch,

  /// 首次启动
  firstLaunch,

  /// 上一次最新版本
  lastLatestVersion,
}

/// 应用设置
class AppSettings {
  AppSettings._();

  static bool get bootLaunch => PrefsUtil.getBool(AppSetting.bootLaunch.toString()) ?? false;
  static set bootLaunch(bool value) => PrefsUtil.setBool(AppSetting.bootLaunch.toString(), value);

  static bool get firstLaunch => PrefsUtil.getBool(AppSetting.firstLaunch.toString()) ?? true;
  static set firstLaunch(bool value) => PrefsUtil.setBool(AppSetting.firstLaunch.toString(), value);

  static String get lastLatestVersion => PrefsUtil.getString(AppSetting.lastLatestVersion.toString()) ?? '';
  static set lastLatestVersion(String value) => PrefsUtil.setString(AppSetting.lastLatestVersion.toString(), value);
}
