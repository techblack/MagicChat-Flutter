package cloud.baizhi.chat

import io.flutter.embedding.android.FlutterActivity
import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "magicchat/notifications"
    private val notificationChannelId = "magicchat_messages"
    private val requestCode = 4101
    private var pendingRouteToken: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingRouteToken = routeTokenFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingRouteToken = routeTokenFromIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "magicchat/push")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceToken" -> {
                        result.success(readJPushDeviceToken())
                    }
                    "getPendingRouteToken" -> {
                        val token = pendingRouteToken
                        pendingRouteToken = null
                        result.success(token)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), requestCode)
                        }
                        result.success(true)
                    }
                    "showMessage" -> {
                        val title = call.argument<String>("title") ?: "新消息"
                        val body = call.argument<String>("body") ?: ""
                        val id = (call.argument<String>("conversation_id") ?: "magicchat").hashCode()
                        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                            NotificationManagerCompat.from(this).notify(id, NotificationCompat.Builder(this, notificationChannelId)
                                .setSmallIcon(android.R.drawable.ic_dialog_info)
                                .setContentTitle(title)
                                .setContentText(body)
                                .setAutoCancel(true)
                                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                                .build())
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readJPushDeviceToken(): Map<String, String>? {
        if (!BuildConfig.JPUSH_CONFIGURED) return null
        return try {
            val jpush = Class.forName("cn.jpush.android.api.JPushInterface")
            jpush.getMethod("setDebugMode", Boolean::class.javaPrimitiveType)
                .invoke(null, BuildConfig.DEBUG)
            jpush.getMethod("init", Context::class.java)
                .invoke(null, applicationContext)
            val registrationId = jpush
                .getMethod("getRegistrationID", Context::class.java)
                .invoke(null, applicationContext) as? String
            val token = registrationId?.trim().orEmpty()
            if (token.isEmpty()) null else mapOf(
                "provider" to "jpush",
                "platform" to "android",
                "environment" to "production",
                "token" to token,
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun routeTokenFromIntent(intent: Intent?): String? {
        val token = intent?.getStringExtra("route_token")?.trim()
        return token?.takeIf { it.isNotEmpty() }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(notificationChannelId, "消息通知", NotificationManager.IMPORTANCE_DEFAULT)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
