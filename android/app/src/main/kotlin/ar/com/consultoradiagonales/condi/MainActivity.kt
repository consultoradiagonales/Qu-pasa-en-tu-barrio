package ar.com.consultoradiagonales.condi

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Marca, modelo y versión de Android, para el perfil de dispositivo que
        // la persona acepta compartir. No requiere ningún permiso.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ar.com.consultoradiagonales.condi/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "info") {
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "model" to Build.MODEL,
                            "osVersion" to Build.VERSION.RELEASE,
                        ),
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
