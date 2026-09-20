import 'dart:convert';
import 'dart:io';

import 'package:video_player_example/common/index.dart';
import 'package:retry/retry.dart';
import 'package:http/http.dart' as http;

final _logger = LoggerUtil.create(['请求']);

/// 网络请求工具
class RequestUtil {
  static late final RetryOptions _r;
  static final Map<String, String> _headers = {};

  static void addOrUpdateHeader(String key, String value) {
    _headers[key] = value;
  }

  static void removeHeader(String key) {
    _headers.remove(key);
  }

  static void init() {
    HttpOverridesUtil.init();

    _r = const RetryOptions(
      maxAttempts: 2,
      delayFactor: Duration(seconds: 2),
      maxDelay: Duration(seconds: 4),
    );
  }

  static Future<String> get(String url,
      {Duration timeout = const Duration(seconds: 15)}) async {
    http.Client? client;
    try {
      client = http.Client();
      final response = await _r.retry(() =>
          client!.get(Uri.parse(url), headers: _headers).timeout(timeout));

      if (response.statusCode == 200) {
        return utf8.decode(response.bodyBytes);
      }
      _logger.warning('请求失败 HTTP ${response.statusCode}: $url');
    }
    catch(ex){
      _logger.debug('请求异常 $url: $ex');
    }
    finally {
      // Future.timeout 只是让这个 Future 提前以异常收场，底层 socket 并不会跟着关。
      // 不显式 close 的话，超时的连接会一直挂在 client 的连接池里：
      // 拉源接口慢或不可达时（半开连接）这些连接不会被回收，越积越多，
      // 之后连正常的请求也发不出去，表现为"进了 App 就一直转"。
      client?.close();
    }
    return '';
  }

  /// 下载文件到本地，支持进度回调
  static Future<String?> download({
    required String url,
    required String savePath,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.headers.addAll(_headers);
        final response = await client
            .send(request)
            .timeout(const Duration(minutes: 5));

        if (response.statusCode != 200) return null;

        final file = File(savePath);
        final sink = file.openWrite();
        final contentLength = response.contentLength ?? -1;
        var received = 0;

        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength > 0 && onProgress != null) {
            onProgress(received / contentLength);
          }
        }
        await sink.close();

        return savePath;
      } finally {
        client.close();
      }
    } catch (e) {
      return null;
    }
  }
}
