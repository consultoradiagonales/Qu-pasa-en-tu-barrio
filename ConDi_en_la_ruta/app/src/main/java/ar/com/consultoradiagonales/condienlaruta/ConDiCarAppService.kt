package ar.com.consultoradiagonales.condienlaruta

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class ConDiCarAppService : CarAppService() {

    override fun createHostValidator(): HostValidator {
        // Para producción reemplazar con whitelist de hosts certificados de Google
        // Ver: https://developer.android.com/training/cars/apps#host-validator
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session = ConDiSession()
}
