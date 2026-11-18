package ar.com.consultoradiagonales.condi.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.core.graphics.drawable.IconCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MapScreen(carContext: CarContext) : Screen(carContext) {

    private val weatherRepo = WeatherRepository()
    private val surfaceRenderer = SurfaceRenderer(carContext)
    private var alertText: String? = null
    private var weatherJob: Job? = null

    init {
        carContext.getCarService(androidx.car.app.AppManager::class.java)
            .setSurfaceCallback(surfaceRenderer)

        NotificationBus.onNewAlert = { alert ->
            alertText = alert
            invalidate()
        }

        weatherJob = CoroutineScope(Dispatchers.IO).launch {
            while (true) {
                val result = weatherRepo.fetchRadarAndAlerts(
                    LocationRepository.currentLat,
                    LocationRepository.currentLng
                )
                surfaceRenderer.updateRadar(result.radarBitmap)
                if (result.alertText != null) {
                    alertText = result.alertText
                }
                invalidate()
                delay(5 * 60 * 1000L)
            }
        }
    }

    override fun onGetTemplate(): Template {
        val alertActionBuilder = ActionStrip.Builder()

        val currentAlert = alertText
        if (currentAlert != null) {
            alertActionBuilder.addAction(
                Action.Builder()
                    .setTitle(currentAlert.take(60))
                    .setBackgroundColor(CarColor.RED)
                    .setOnClickListener { alertText = null; invalidate() }
                    .build()
            )
        }

        return NavigationTemplate.Builder()
            .setActionStrip(alertActionBuilder.build())
            .setMapActionStrip(
                ActionStrip.Builder()
                    .addAction(NavigationTemplate.PAN_BUTTON)
                    .build()
            )
            .build()
    }

    override fun onStop() {
        weatherJob?.cancel()
        NotificationBus.onNewAlert = null
    }
}
