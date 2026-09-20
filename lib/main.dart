import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fijkplayer_ijkfix/fijkplayer_ijkfix.dart';
import 'package:get_it/get_it.dart';
import 'package:video_player_example/common/index.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player_example/common/widgets/restart.dart';
import 'package:video_player_example/pages/index.dart';

import 'common/utils/security_check.dart';
import 'common/widgets/delay_renderer.dart';
//import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 强制横屏
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);

  // 小白条、导航栏沉浸
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarColor: Colors.transparent,
  ));

  // 保持屏幕常亮
  //WakelockPlus.enable();

  // 初始化
  await PrefsUtil.init();
  LoggerUtil.init();
  RequestUtil.init();
  // 源健康度记录（哪些源播过失败）。未载入时退化为"所有源一样优先"，
  // 不阻塞启动，所以放在这里而不是更早。
  await SourceHealthUtil.load();

  // fijkplayer 的日志级别默认是 Info，而 FijkLog.log 内部直接 print，
  // release 包同样会往 logcat 刷。这里按构建模式收敛。
  // （Android 上该接口会触发加载 native 库，所以放在创建 FijkPlayer 之前即可）
  FijkLog.setLevel(kDebugMode ? FijkLogLevel.Info : FijkLogLevel.Silent);

  // 注册全局Store
  GetIt.I.registerSingleton(PlayerStore());
  GetIt.I.registerSingleton(IptvStore());
  GetIt.I.registerSingleton(UpdateStore());

  // 读取收藏频道
  await GetIt.I<IptvStore>().loadFavorites();

  // root / 模拟器检测
  final isRooted = await SecurityCheck.isRooted();
  final isEmulator = await SecurityCheck.isEmulator();
  if (isRooted || isEmulator) {
    runApp(UnsafeDeviceApp(isRooted: isRooted, isEmulator: isEmulator));
    return;
  }

  runApp(const MyApp());
}

/// Root/模拟器设备提示页
class UnsafeDeviceApp extends StatelessWidget {
  final bool isRooted;
  final bool isEmulator;

  const UnsafeDeviceApp({super.key, required this.isRooted, required this.isEmulator});

  @override
  Widget build(BuildContext context) {
    final reasons = <String>[];
    if (isRooted) reasons.add('设备已 Root');
    if (isEmulator) reasons.add('模拟器环境');

    return MaterialApp(
      home: PopScope(
        canPop: false,
        onPopInvoked: (bool didPop) {
          if (didPop) return;
          SystemNavigator.pop();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 64),
                const SizedBox(height: 24),
                Text(
                  '安全风险',
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  reasons.join('，'),
                  style: TextStyle(color: Colors.orange.shade300, fontSize: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  '为了安全起见，应用已退出',
                  style: TextStyle(color: Colors.white54, fontSize: 20),
                ),
                const SizedBox(height: 32),
                // 兜底：这是页面唯一可聚焦的控件，
                // 即便检测误判（部分电视盒子固件会被识别为 Root/模拟器），
                // 用户也能用遥控器 OK 键退出，而不是卡死。
                OutlinedButton(
                  autofocus: true,
                  onPressed: () => SystemNavigator.pop(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text(
                      '退出应用',
                      style: TextStyle(fontSize: 20, decoration: TextDecoration.none),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const colorScheme = ColorScheme.dark(background: Colors.black);

    return ScreenUtilInit(
      designSize: const Size(1920, 1080),
      minTextAdapt: true,
      splitScreenMode: true,
      child: RestartWidget(
          child: MaterialApp(
            title: 'HTV',
            theme: ThemeData(
              colorScheme: colorScheme,
            ),
            localizationsDelegates: const [...GlobalMaterialLocalizations.delegates, GlobalWidgetsLocalizations.delegate],
            supportedLocales: const [Locale("zh", "CH"), Locale("en", "US")],
            home: const DelayRenderer(
              child: DoubleBackExit(
                child: IptvPage(),
              ),
            ),
          ),
      ),
    );
  }
}
