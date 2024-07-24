import 'package:talker_flutter/talker_flutter.dart';

class Logger {
  late final List<String> prefixList;

  Logger._(this.prefixList);

  String? _resolveMsg(dynamic msg) {
    if (msg == null) return null;

    return '${prefixList.map((it) => '[$it]').join(' ')} $msg';
  }

  void verbose(dynamic msg) => LoggerUtil.logger.verbose(_resolveMsg(msg));

  void debug(dynamic msg) => LoggerUtil.logger.debug(_resolveMsg(msg));

  void info(dynamic msg) => LoggerUtil.logger.info(_resolveMsg(msg));

  void warning(dynamic msg) => LoggerUtil.logger.warning(_resolveMsg(msg));

  void error(dynamic msg, [Object? exception, StackTrace? stackTrace]) =>
      LoggerUtil.logger.error(_resolveMsg(msg), exception, stackTrace);

  void handle(Object exception, [StackTrace? stackTrace, dynamic msg]) =>
      LoggerUtil.logger.handle(exception, stackTrace, _resolveMsg(msg));
}

/// 日志工具
class LoggerUtil {
  static late final Talker logger;

  LoggerUtil._();

  /// 初始化
  static init() {
    logger = TalkerFlutter.init(settings: TalkerSettings(useHistory: false));
  }

  static void verbose(dynamic msg) => logger.verbose(msg);

  static void debug(dynamic msg) => logger.debug(msg);

  static void info(dynamic msg) => logger.info(msg);

  static void warning(dynamic msg) => logger.warning(msg);

  static void error(dynamic msg, [Object? exception, StackTrace? stackTrace]) =>
      logger.error(msg, exception, stackTrace);

  static void handle(Object exception, [StackTrace? stackTrace, dynamic msg]) =>
      logger.handle(exception, stackTrace, msg);

  static Logger create(List<String> prefixList) {
    return Logger._(prefixList);
  }
}
