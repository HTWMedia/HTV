# ─── Flutter 核心类（必须保留）─────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# ─── @Keep 注解类 ─────────────────────────
-keep @androidx.annotation.Keep class * { *; }

# ─── ijkplayer / fijkplayer（JNI 反射调用，必须保留）─────────────
# ijkplayer 的 Java 层大量通过 JNI 按类名+方法签名反射调用，
# 配合下面的 -repackageclasses '' / -overloadaggressively 会被混淆破坏，
# 导致 release 包启动或播放时崩溃（debug 关闭混淆所以不复现）。
-keep class tv.danmaku.ijk.media.player.** { *; }
-keep class com.example.fijkplayer_ijkfix.** { *; }
-keepnames class tv.danmaku.ijk.media.player.** { *; }
-keepclassmembers class tv.danmaku.ijk.media.player.** {
    native <methods>;
}

# Flutter 插件入口：本项目的 FijkPlugin 实现的是新接口
# io.flutter.embedding.engine.plugins.FlutterPlugin，上面那条旧接口规则覆盖不到。
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware { *; }

# ─── 平台通道 ─────────────────────────────
-keep class * extends io.flutter.plugin.common.MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry.Plugin { *; }

# ─── 资源类（R 文件）─────────────────────
-keep class **.R$* { *; }

# ─── 移除日志 ─────────────────────────────
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
    public static java.lang.String getStackTraceString(java.lang.Throwable);
}
-assumenosideeffects class java.lang.Throwable {
    public void printStackTrace();
}

# ─── 移除调试信息 ─────────────────────────
-renamesourcefileattribute N/A
-keepattributes SourceFile,LineNumberTable
-dontwarn
-optimizationpasses 5
-mergeinterfacesaggressively
-overloadaggressively
-repackageclasses ''
-allowaccessmodification
-flattenpackagehierarchy ''
