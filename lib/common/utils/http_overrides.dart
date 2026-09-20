import 'dart:io';

/// 修复部分 HTTPS 证书过期问题
/// 仅对已知有证书问题的域名跳过验证，而非全局放行
class _HttpOverrides extends HttpOverrides {
  // 已知证书有问题的域名列表（证书过期 / 自签名）
  static const _insecureHosts = <String>{
    'mirror.ghproxy.com',
    'node1.olelive.com',
  };

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // 仅对已知域名跳过证书验证
        if (_insecureHosts.any((h) => host.contains(h))) {
          return true;
        }
        return false;
      };
  }
}

class HttpOverridesUtil {
  HttpOverridesUtil._();

  static void init() {
    HttpOverrides.global = _HttpOverrides();
  }
}
