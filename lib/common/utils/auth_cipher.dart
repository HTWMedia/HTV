/// 取源接口的鉴权串生成 —— 开源桩实现。
///
/// 本仓库遵循「壳源分离」：只发布 App 外壳，不发布服务端鉴权的任何细节
/// （算法、密钥、IV 均不随仓库分发）。因此这里只有一个空实现：
/// [encrypt] 返回空串，调用方据此不携带 authorization 头，
/// 服务端按匿名请求返回公网列表。
///
/// 自建服务端 / 需要鉴权的人：把这里替换成自己的实现，
/// 保证返回值与服务端的校验规则一致即可，其余代码无需改动。
class AuthCipher {
  AuthCipher._();

  /// 返回空串表示「本次请求不携带 authorization 头」。
  static String encrypt(String plainText) => '';
}
