package ar.com.consultoradiagonales.condi.auto

import android.content.Intent
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session

class ConDiSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        LocationRepository.startTracking(carContext)
        return MapScreen(carContext)
    }
}
