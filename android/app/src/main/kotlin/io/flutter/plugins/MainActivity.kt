package io.flutter.plugins

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.htwmedia.htv/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isRooted" -> result.success(isDeviceRooted())
                "isEmulator" -> result.success(isEmulator())
                else -> result.notImplemented()
            }
        }
    }

    private fun isDeviceRooted(): Boolean {
        // 1. 检查常见 su 路径
        val suPaths = arrayOf(
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su"
        )
        for (path in suPaths) {
            if (File(path).exists()) return true
        }

        // 2. 检查 Magisk
        if (File("/data/adb/magisk").exists()) return true
        if (File("/data/adb/magisk.db").exists()) return true

        // 3. 检查 SuperSU
        if (File("/data/data/eu.chainfire.supersu").exists()) return true

        // 4. 从 PATH 中查找 su
        return hasSuExecutable()

        // 注意：不以 Build.TAGS 的 "test-keys" 单独判定。
        // 大量国产电视、盒子的出厂固件本身就是 test-keys 签名，
        // 据此判定会造成大面积误杀，且用户拿到的是一个退不出去的提示页。
    }

    private fun hasSuExecutable(): Boolean {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("which", "su"))
            val result = process.inputStream.bufferedReader().readText().trim()
            process.destroy()
            result.isNotEmpty()
        } catch (_: Exception) {
            false
        }
    }

    private fun isEmulator(): Boolean {
        // 虚拟化代号：goldfish / ranchu / qemu 是模拟器专属底层标识
        if (Build.HARDWARE.contains("goldfish", ignoreCase = true) ||
            Build.HARDWARE.contains("ranchu", ignoreCase = true) ||
            Build.HARDWARE.contains("qemu", ignoreCase = true)) {
            return true
        }

        if (Build.MANUFACTURER.contains("genymotion", ignoreCase = true)) return true

        if (Build.MODEL.contains("google_sdk", ignoreCase = true) ||
            Build.MODEL.contains("emulator", ignoreCase = true) ||
            Build.MODEL.contains("android sdk built for", ignoreCase = true)) {
            return true
        }

        if (Build.PRODUCT == "google_sdk" ||
            Build.PRODUCT.startsWith("sdk_gphone") ||
            Build.PRODUCT.contains("vbox86", ignoreCase = true)) {
            return true
        }

        // brand 与 device 同时为 generic 才判定模拟器；
        // 单独 brand 为 generic 在第三方盒子上很常见
        return Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic")

        // 注意：已移除 Build.FINGERPRINT.startsWith("unknown") 判定。
        // 国产盒子的 FINGERPRINT 常以 unknown 开头（如 unknown/rk3399/rk3399:...），
        // 该条件曾经让正常电视直接变成无法操作的提示页。
    }
}
