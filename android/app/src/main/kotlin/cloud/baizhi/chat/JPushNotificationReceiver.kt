package cloud.baizhi.chat

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import cn.jpush.android.api.JPushInterface
import cn.jpush.android.api.NotificationMessage
import cn.jpush.android.service.JPushMessageReceiver
import org.json.JSONObject

/** JPush 后台通知适配器，只接受 Push Gateway 的 route token。 */
class JPushNotificationReceiver : JPushMessageReceiver() {
    override fun isNeedShowNotification(
        context: Context,
        message: NotificationMessage,
        notificationChannel: String,
    ): Boolean {
        val process = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(process)
        return process.importance > ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    }

    override fun onNotifyMessageArrived(context: Context, message: NotificationMessage) {
        val collapseKey = runCatching {
            JSONObject(message.notificationExtras.orEmpty())
                .optString("collapse_key")
                .trim()
        }.getOrDefault("")
        if (collapseKey.isEmpty() || message.notificationId <= 0) return
        val preferences = context.applicationContext.getSharedPreferences(
            "magicchat.jpush.collapsed-notifications",
            Context.MODE_PRIVATE,
        )
        val previous = preferences.getInt(collapseKey, 0)
        if (previous > 0 && previous != message.notificationId) {
            JPushInterface.clearNotificationById(context.applicationContext, previous)
        }
        preferences.edit().putInt(collapseKey, message.notificationId).apply()
    }

    override fun onNotifyMessageOpened(context: Context, message: NotificationMessage) {
        val routeToken = runCatching {
            JSONObject(message.notificationExtras.orEmpty())
                .optString("route_token")
                .trim()
        }.getOrDefault("")
        if (routeToken.length < 32) return
        context.applicationContext
            .getSharedPreferences("magicchat.push", Context.MODE_PRIVATE)
            .edit()
            .putString("pending_route_token", routeToken)
            .apply()
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            context.startActivity(it)
        }
    }
}
