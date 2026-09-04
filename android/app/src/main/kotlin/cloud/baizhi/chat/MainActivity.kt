package cloud.baizhi.chat

import io.flutter.embedding.android.FlutterActivity
import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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
    private val unreadGroup = "magicchat_unread"
    private val badgeNotificationId = 4102
    private val requestCode = 4101
    private var pendingRouteToken: String? = null
    private var pendingConversationId: String? = null
    private var pendingMessageId: String? = null
    private var pushChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        rememberRoute(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        rememberRoute(intent)
        pushChannel?.invokeMethod("routeOpened", pendingRoute())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
        pushChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "magicchat/push")
        pushChannel!!
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
                    "getPendingRoute" -> {
                        val route = pendingRoute()
                        pendingRouteToken = null
                        pendingConversationId = null
                        pendingMessageId = null
                        result.success(route)
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
                        val conversationId = call.argument<String>("conversation_id") ?: "magicchat"
                        val messageId = call.argument<String>("message_id") ?: ""
                        val id = conversationId.hashCode()
                        val routeIntent = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            putExtra("conversation_id", conversationId)
                            putExtra("message_id", messageId)
                        }
                        val routePendingIntent = PendingIntent.getActivity(
                            this,
                            id,
                            routeIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                            NotificationManagerCompat.from(this).notify(id, NotificationCompat.Builder(this, notificationChannelId)
                                .setSmallIcon(android.R.drawable.ic_dialog_info)
                                .setContentTitle(title)
                                .setContentText(body)
                                .setContentIntent(routePendingIntent)
                                .setGroup(unreadGroup)
                                .setNumber(1)
                                .setAutoCancel(true)
                                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                                .build())
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "magicchat/app_badge")
            .setMethodCallHandler { call, result ->
                if (call.method != "setCount") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val count = (call.argument<Number>("count")?.toInt() ?: 0).coerceAtLeast(0)
                val manager = NotificationManagerCompat.from(this)
                if (count == 0) {
                    manager.cancel(badgeNotificationId)
                } else if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                    val launchIntent = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    val launchPendingIntent = PendingIntent.getActivity(
                        this,
                        badgeNotificationId,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                    manager.notify(badgeNotificationId, NotificationCompat.Builder(this, notificationChannelId)
                        .setSmallIcon(android.R.drawable.ic_dialog_info)
                        .setContentTitle("MagicChat")
                        .setContentText("$count 条未读消息")
                        .setContentIntent(launchPendingIntent)
                        .setGroup(unreadGroup)
                        .setGroupSummary(true)
                        .setNumber(count)
                        .setOnlyAlertOnce(true)
                        .setSilent(true)
                        .setOngoing(true)
                        .setPriority(NotificationCompat.PRIORITY_LOW)
                        .build())
                }
                result.success(true)
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

    private fun rememberRoute(intent: Intent?) {
        pendingRouteToken = routeTokenFromIntent(intent)
        pendingConversationId = intent?.getStringExtra("conversation_id")
            ?.trim()?.takeIf { it.isNotEmpty() }
        pendingMessageId = intent?.getStringExtra("message_id")
            ?.trim()?.takeIf { it.isNotEmpty() }
    }

    private fun pendingRoute() = mapOf(
        "route_token" to (pendingRouteToken ?: ""),
        "conversation_id" to (pendingConversationId ?: ""),
        "message_id" to (pendingMessageId ?: ""),
    )

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(notificationChannelId, "消息通知", NotificationManager.IMPORTANCE_DEFAULT)
            channel.setShowBadge(true)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
