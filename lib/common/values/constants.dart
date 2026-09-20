/// 常量
class Constants {
  /// 默认源服务地址（内置源的默认取值）
  ///
  /// 壳源分离：App 自带的是一个**可替换的服务地址**，不是任何频道数据；
  /// 用户可在「设置 → 直播源 → 默认源服务」里改成自己的订阅接口，或清空表示不启用内置源
  /// （清空后只加载「自定义直播源」）。改动走 Prefs，服务端接入方不需要改代码。
  static const defaultIptvSourceApi = 'https://htwmedia.dpdns.org/Home/IPTVSearch';

  /// 直播源缓存时间
  static const iptvSourceCacheKeepTime = 1000 * 60 * 60; // 1小时

  /// epg xml
  static const iptvEpgXml = 'https://htwmedia.dpdns.org/Home/getepg';

  /// epg 刷新时间阈值（小时）
  static const epgRefreshTimeThreshold = 6; // 不到6点不刷新

  /// github API 获取最新 release
  static const githubReleaseApi = 'https://api.github.com/repos/HTWMedia/HTV/releases/latest';

  /// github代理加速地址
  static const githubProxy = 'https://mirror.ghproxy.com/';

  /// github release latest (fallback HTML 页面)
  static const githubReleaseLatest = 'https://github.com/HTWMedia/HTV/releases/latest';

  /// 设置服务器端口
  static const httpServerPort = 10381;

  /// http请求重试次数
  static const httpRetryCount = 10;

  /// HTTP请求重试间隔时间（毫秒）
  static const httpRetryInterval = 3000;
}
