package io.flutter.plugins

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED == intent.action) {
            val prefs: SharedPreferences =
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val bootLaunch = prefs.getBoolean("flutter.AppSetting.bootLaunch", false)

            if(bootLaunch) {
                val i = Intent(context, MainActivity::class.java)
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(i)
            }
        }
    }
}
