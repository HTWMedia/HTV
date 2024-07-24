import 'dart:convert';

import 'package:video_player_example/common/index.dart';
import 'package:retry/retry.dart';
import 'package:http/http.dart' as http;

/// 网络请求工具
class RequestUtil {
  static late final RetryOptions _r;

  static void init() {
    HttpOverridesUtil.init();

    _r = const RetryOptions(
      maxAttempts: 10,
      delayFactor: Duration(seconds: 1),
      maxDelay: Duration(seconds: 5),
    );
  }

  static Future<String> get(String url) async {
    final response = await _r.retry(() => http.get(Uri.parse(url)));

    if (response.statusCode != 200) {
      throw Exception('请求失败: ${response.statusCode}: ${response.reasonPhrase}');
    }

    return utf8.decode(response.bodyBytes);
  }
}
