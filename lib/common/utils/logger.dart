import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart';

class Logger {
  late final List<String> prefixList;

  Logger._(this.prefixList);

  String? _resolveMsg(dynamic msg) {
    if (msg == null) return null;

    return '${prefixList.map((it) => '[$it]').join(' ')} $msg';
  }

  void verbose(dynamic msg) {
    if (!LoggerUtil.enabled) return;
    LoggerUtil.logger.verbose(_resolveMsg(msg));
  }

  void debug(dynamic msg) {
    if (!LoggerUtil.enabled) return;
    LoggerUtil.logger.debug(_resolveMsg(msg));
  }

  void info(dynamic msg) {
    if (!LoggerUtil.enabled) return;
    LoggerUtil.logger.info(_resolveMsg(msg));
  }

  void warning(dynamic msg) {
    if (!LoggerUtil.enabled) return;
    LoggerUtil.logger.warning(_resolveMsg(msg));
  }

  void error(dynamic msg, [Object? exception, StackTrace? stackTrace]) {
    if (!LoggerUtil.enabled) return;
    LoggerUtil.logger.error(_resolveMsg(msg), exception, stackTrace);
  }

  void handle(Object exception, [StackTrace? stackTrace, dynamic msg]) {
    if (!LoggerUtil.enabled) return;
    LoggerUtil.logger.handle(exception, stackTrace, _resolveMsg(msg));
  }
}

/// 日志工具
class LoggerUtil {
  static Talker? _logger;

  /// 日志实现。
  ///
  /// 惰性构造：晚于 main() 才被首次访问时（例如单测直接跑业务代码、
  /// 或将来某条启动路径调整了 init() 的位置）不会因为没初始化而把整条
  /// 调用链炸掉。日志是可有可无的东西，它不应该有能力让业务挂掉。
  static Talker get logger => _logger ??= TalkerFlutter.init(
        settings: TalkerSettings(
          enabled: enabled,
          useHistory: false,
          useConsoleLogs: false,
        ),
      );

  /// 日志总开关。release 包整体关闭。
  ///
  /// 每个 Logger 方法都在开关为 false 时直接 return：
  /// 调用方的字符串插值（如 '播放直播源: $iptv'）发生在入参求值阶段，
  /// 只有提前返回才能真正省掉这部分开销，
  /// 而不是等 Talker 内部过滤时才发现不该打印。
  static bool enabled = true;

  LoggerUtil._();

  /// 初始化
  ///
  /// Talker 默认 enabled=true 且会向 console 输出，
  /// release 包需要显式关闭。排查线上问题时把 [enabled] 改成 true 重打包即可。
  static init() {
    enabled = kDebugMode;
    _logger = TalkerFlutter.init(
      settings: TalkerSettings(
        enabled: kDebugMode,
        useHistory: kDebugMode,
        useConsoleLogs: kDebugMode,
      ),
    );
  }

  static void verbose(dynamic msg) {
    if (!enabled) return;
    logger.verbose(msg);
  }

  static void debug(dynamic msg) {
    if (!enabled) return;
    logger.debug(msg);
  }

  static void info(dynamic msg) {
    if (!enabled) return;
    logger.info(msg);
  }

  static void warning(dynamic msg) {
    if (!enabled) return;
    logger.warning(msg);
  }

  static void error(dynamic msg, [Object? exception, StackTrace? stackTrace]) {
    if (!enabled) return;
    logger.error(msg, exception, stackTrace);
  }

  static void handle(Object exception, [StackTrace? stackTrace, dynamic msg]) {
    if (!enabled) return;
    logger.handle(exception, stackTrace, msg);
  }

  static Logger create(List<String> prefixList) {
    return Logger._(prefixList);
  }
}
