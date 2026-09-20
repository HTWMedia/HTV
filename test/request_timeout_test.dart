import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_example/common/utils/request.dart';

Future<HttpServer> _startSlowServer({required Duration delay}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    await Future<void>.delayed(delay);
    request.response.write('slow-body');
    await request.response.close();
  });
  return server;
}

void main() {
  setUpAll(() => RequestUtil.init());

  test('自定义超时：短超时在慢服务器上返回空串', () async {
    final server = await _startSlowServer(delay: const Duration(milliseconds: 800));
    try {
      final result = await RequestUtil.get(
        'http://127.0.0.1:${server.port}/',
        timeout: const Duration(milliseconds: 200),
      );
      expect(result, '');
    } finally {
      await server.close(force: true);
    }
  });

  test('自定义超时：足够长的超时在慢服务器上返回内容', () async {
    final server = await _startSlowServer(delay: const Duration(milliseconds: 800));
    try {
      final result = await RequestUtil.get(
        'http://127.0.0.1:${server.port}/',
        timeout: const Duration(seconds: 5),
      );
      expect(result, 'slow-body');
    } finally {
      await server.close(force: true);
    }
  });
}
