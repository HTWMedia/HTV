/// 常量
class Constants {
  /// 直播源
  static const iptvSource = 'https://mirror.ghproxy.com/https://raw.githubusercontent.com/zhumeng11/IPTV/main/IPTV.m3u';

  /// 直播源缓存时间
  static const iptvSourceCacheKeepTime = 1000 * 60 * 60 * 24; // 24小时

  /// epg xml
  static const iptvEpgXml = 'https://live.fanmingming.com/e.xml';

  /// epg 刷新时间阈值（小时）
  static const epgRefreshTimeThreshold = 6; // 不到6点不刷新

  /// github release latest
  static const githubReleaseLatest = 'https://api.github.com/repos/yaoxieyoulei/my_tv/releases/latest';

  /// github代理加速地址
  static const githubProxy = 'https://mirror.ghproxy.com/';

  /// 设置服务器端口
  static const httpServerPort = 10381;

  /// http请求重试次数
  static const httpRetryCount = 10;

  /// HTTP请求重试间隔时间（毫秒）
  static const httpRetryInterval = 3000;
}
