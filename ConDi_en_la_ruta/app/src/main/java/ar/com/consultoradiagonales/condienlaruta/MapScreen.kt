package ar.com.consultoradiagonales.condienlaruta

import android.graphics.Rect
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.*

class MapScreen(carContext: CarContext) : Screen(carContext) {

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val weatherRepo = WeatherRepository()
    private val surfaceRenderer = SurfaceRenderer()

    private var stormAlert: String? = null
    private var latestPhoneAlert: String? = null

    init {
        // Registrar callback de Surface para dibujar el mapa
        carContext.getCarService(AppManager::class.java)
            .setSurfaceCallback(surfaceRenderer)

        // Escuchar alertas del celular
        NotificationBus.onNewAlert = { text ->
            latestPhoneAlert = text
            invalidate()
        }

        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                startWeatherLoop()
            }
            override fun onDestroy(owner: LifecycleOwner) {
                scope.cancel()
                NotificationBus.onNewAlert = null
            }
        })
    }

    override fun onGetTemplate(): Template {
        val alertText = latestPhoneAlert ?: stormAlert ?: carContext.getString(R.string.no_alerts)

        return NavigationTemplate.Builder()
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle(alertText)
                            .setOnClickListener { /* cerrar alerta */ latestPhoneAlert = null; invalidate() }
                            .build()
                    )
                    .build()
            )
            .setMapActionStrip(
                ActionStrip.Builder()
                    .addAction(Action.PAN)
                    .build()
            )
            .build()
    }

    private fun startWeatherLoop() {
        scope.launch {
            while (isActive) {
                try {
                    val result = weatherRepo.fetchRadarAndAlerts(
                        lat = LocationRepository.currentLat,
                        lng = LocationRepository.currentLng
                    )
                    surfaceRenderer.updateRadar(result)
                    stormAlert = result.alertText
                    invalidate()
                } catch (_: Exception) {}
                delay(5 * 60 * 1000L) // actualizar cada 5 minutos
            }
        }
    }
}
