package ar.com.consultoradiagonales.condienlaruta

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle

/**
 * Singleton que mantiene la posición GPS actual.
 * Default: Buenos Aires (se actualiza en cuanto llega el primer fix GPS).
 */
object LocationRepository {

    var currentLat: Double = -34.6037
    var currentLng: Double = -58.3816

    @SuppressLint("MissingPermission")
    fun startTracking(context: Context) {
        val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                currentLat = location.latitude
                currentLng = location.longitude
            }
            @Deprecated("Deprecated in API level 29")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        try {
            // GPS primero; si no hay, red
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 10_000L, 50f, listener)
            } else if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 15_000L, 100f, listener)
            }
        } catch (_: SecurityException) {}
    }
}
