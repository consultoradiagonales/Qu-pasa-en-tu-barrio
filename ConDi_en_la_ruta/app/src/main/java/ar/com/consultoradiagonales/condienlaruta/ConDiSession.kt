package ar.com.consultoradiagonales.condienlaruta

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

class ConDiSession : Session() {

    override fun onCreateScreen(intent: Intent): Screen {
        // Iniciar seguimiento de ubicación al arrancar la sesión
        LocationRepository.startTracking(carContext)
        return MapScreen(carContext)
    }
}
