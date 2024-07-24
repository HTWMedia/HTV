import 'dart:io';

/// 修复部分设备 CERTIFICATE_VERIFY_FAILED: certificate has expired
class _HttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class HttpOverridesUtil {
  HttpOverridesUtil._();

  static void init() {
    HttpOverrides.global = _HttpOverrides();
  }
}
