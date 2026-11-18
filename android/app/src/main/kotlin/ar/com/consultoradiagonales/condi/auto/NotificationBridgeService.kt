package ar.com.consultoradiagonales.condi.auto

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

object NotificationBus {
    val latestAlerts = ArrayDeque<String>(10)
    var onNewAlert: ((String) -> Unit)? = null
}

class NotificationBridgeService : NotificationListenerService() {

    private val allowedPackages = setOf(
        "ar.com.consultoradiagonales.condi",
        "com.whatsapp",
        "com.google.android.apps.messaging",
        "com.android.phone"
    )

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        val extras = sbn.notification.extras
        val isHighPriority = sbn.notification.priority >= android.app.Notification.PRIORITY_HIGH

        if (pkg !in allowedPackages && !isHighPriority) return

        val title = extras.getString("android.title") ?: return
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val alert = "[$title] $text".take(120)

        with(NotificationBus) {
            latestAlerts.addFirst(alert)
            if (latestAlerts.size > 10) latestAlerts.removeLast()
            onNewAlert?.invoke(alert)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {}
}
