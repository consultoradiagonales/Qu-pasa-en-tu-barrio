package ar.com.consultoradiagonales.condienlaruta

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Bus singleton: la MapScreen se suscribe con onNewAlert para
 * recibir notificaciones del celular en tiempo real.
 */
object NotificationBus {
    val latestAlerts = ArrayDeque<String>(10)
    var onNewAlert: ((String) -> Unit)? = null
}

/**
 * Escucha notificaciones del celular y las reenvía a la pantalla del auto.
 * El usuario debe conceder el permiso en Ajustes → Acceso a notificaciones.
 */
class NotificationBridgeService : NotificationListenerService() {

    // Paquetes de los que se reenvían notificaciones al auto
    private val allowedPackages = setOf(
        "ar.com.consultoradiagonales.condi",   // ConDi (alertas propias)
        "com.whatsapp",
        "com.google.android.apps.messaging",   // SMS
        "com.android.phone"                    // llamadas
    )

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        val extras = sbn.notification.extras
        val isHighPriority = sbn.notification.priority >= android.app.Notification.PRIORITY_HIGH

        if (pkg !in allowedPackages && !isHighPriority) return

        val title = extras.getString("android.title") ?: return
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val alert = "[$title] $text".take(120)  // truncar para no saturar la pantalla del auto

        with(NotificationBus) {
            latestAlerts.addFirst(alert)
            if (latestAlerts.size > 10) latestAlerts.removeLast()
            onNewAlert?.invoke(alert)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {}
}
