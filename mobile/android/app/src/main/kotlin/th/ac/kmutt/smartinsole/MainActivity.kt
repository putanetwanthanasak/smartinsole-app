package th.ac.kmutt.smartinsole

import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The camera plugin mirrors the front preview only when the engine's
        // surface producer does not handle crop and rotation itself; the
        // foot check asks the same question so the front preview is always
        // mirrored (lib/footcheck/plugin_foot_camera.dart, S8C).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartinsole/camera_preview")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "handlesCropAndRotation" -> {
                        val producer = flutterEngine.renderer.createSurfaceProducer()
                        try {
                            result.success(producer.handlesCropAndRotation())
                        } finally {
                            producer.release()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Whether the evening reminder can actually show, read on every API
        // level from all three places a phone can block it; the Note 10
        // (Android 12) blocked the app with the app-op alone (S8C).
        // lib/notify/notification_access.dart decides from these.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartinsole/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "sdk" to Build.VERSION.SDK_INT,
                            "enabled" to getSystemService(NotificationManager::class.java)
                                .areNotificationsEnabled(),
                            "permission" to (Build.VERSION.SDK_INT < 33 ||
                                checkSelfPermission("android.permission.POST_NOTIFICATIONS") ==
                                PackageManager.PERMISSION_GRANTED),
                            "appOpAllowed" to postNotificationOpAllowed(),
                        ),
                    )
                    "openSettings" -> {
                        startActivity(notificationSettingsIntent())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun postNotificationOpAllowed(): Boolean {
        val ops = getSystemService(AppOpsManager::class.java)
        val uid = applicationInfo.uid
        val mode = try {
            if (Build.VERSION.SDK_INT >= 29) {
                ops.unsafeCheckOpNoThrow("android:post_notification", uid, packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow("android:post_notification", uid, packageName)
            }
        } catch (e: IllegalArgumentException) {
            return true // op unknown on this phone: nothing blocks there
        }
        return mode != AppOpsManager.MODE_IGNORED && mode != AppOpsManager.MODE_ERRORED
    }

    /// The app's notification settings page (Android 8+), else its app page.
    private fun notificationSettingsIntent(): Intent =
        if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(android.net.Uri.fromParts("package", packageName, null))
        }
}
