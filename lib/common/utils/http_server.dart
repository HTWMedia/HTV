import 'dart:io';

import 'package:flutter/services.dart';
import 'package:video_player_example/common/index.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

final _logger = LoggerUtil.create(['http_server']);

class HttpServerUtil {
  HttpServerUtil._();

  static var _isInitialized = false;

  static String serverUrl = 'http://0.0.0.0:${Constants.httpServerPort}';

  static Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    var app = Router();

    app.get('/', (request) async {
      return shelf.Response.ok(
        await rootBundle.loadString('assets/web/index.html'),
        headers: {'content-type': 'text/html'},
      );
    });

    app.get('/api/IptvSettings/customIptvSource', (request) async {
      var source = request.url.queryParameters['source'] as String;

      _logger.debug('设置自定义直播源: $source');
      IptvSettings.customIptvSource = source;
      IptvSettings.iptvSourceSimplify = false;
      IptvSettings.iptvSourceCacheTime = 0;
      IptvSettings.epgCacheHash = 0;

      return shelf.Response.ok('success');
    });

    var handler = const shelf.Pipeline().addMiddleware(shelf.logRequests()).addHandler(app.call);

    var server = await io.serve(handler, InternetAddress.anyIPv4, Constants.httpServerPort);

    _isInitialized = true;
    serverUrl = 'http://${await _getLocalIPV4()}:${server.port}';
    _logger.debug('启动 $serverUrl');
  }

  static Future<String> _getLocalIPV4() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          return addr.address;
        }
      }
    }

    return '0.0.0.0';
  }
}
