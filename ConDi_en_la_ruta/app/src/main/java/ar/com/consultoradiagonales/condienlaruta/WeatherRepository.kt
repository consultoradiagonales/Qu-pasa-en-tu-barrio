package ar.com.consultoradiagonales.condienlaruta

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit
import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.tan

data class WeatherResult(
    val radarBitmap: Bitmap?,
    val alertText: String?
)

/**
 * Obtiene tiles de radar meteorológico de RainViewer (gratuito, sin API key).
 * Documentación: https://www.rainviewer.com/api/weather-maps-api.html
 */
class WeatherRepository {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    suspend fun fetchRadarAndAlerts(
        lat: Double = -34.6037,
        lng: Double = -58.3816,
        zoom: Int = 6
    ): WeatherResult = withContext(Dispatchers.IO) {

        // 1. Obtener el path del frame de radar más reciente
        val radarPath = fetchLatestRadarPath()
            ?: return@withContext WeatherResult(null, null)

        // 2. Calcular coordenadas de tile para la posición actual
        val (tileX, tileY) = latLngToTile(lat, lng, zoom)

        // 3. Descargar tile del radar
        // Formato: /{timestamp}/{size}/{zoom}/{x}/{y}/{color}/{options}.png
        val url = "https://tilecache.rainviewer.com${radarPath}/256/$zoom/$tileX/$tileY/2/1_1.png"
        val radarBitmap = downloadBitmap(url)

        // 4. Detectar tormenta intensa por color en el tile (rojo/violeta = precipitación fuerte)
        val alertText = if (radarBitmap != null && hasIntenseRain(radarBitmap))
            "⚠️ Lluvia intensa en la ruta"
        else null

        WeatherResult(radarBitmap, alertText)
    }

    private fun fetchLatestRadarPath(): String? {
        return try {
            val json = client.newCall(
                Request.Builder()
                    .url("https://api.rainviewer.com/public/weather-maps.json")
                    .build()
            ).execute().body?.string() ?: return null
            extractLastRadarPath(json)
        } catch (_: Exception) { null }
    }

    private fun downloadBitmap(url: String): Bitmap? {
        return try {
            val response = client.newCall(Request.Builder().url(url).build()).execute()
            BitmapFactory.decodeStream(response.body?.byteStream())
        } catch (_: Exception) { null }
    }

    // Rojo/violeta en el palette de RainViewer = lluvia fuerte o granizo
    private fun hasIntenseRain(bmp: Bitmap): Boolean {
        for (y in 0 until bmp.height step 8) {
            for (x in 0 until bmp.width step 8) {
                val pixel = bmp.getPixel(x, y)
                if (Color.alpha(pixel) < 100) continue
                val r = Color.red(pixel)
                val g = Color.green(pixel)
                if (r > 150 && g < 80) return true
            }
        }
        return false
    }

    // Parseo manual del JSON de RainViewer para extraer el path del último frame
    private fun extractLastRadarPath(json: String): String? {
        return try {
            val pastSection = json.substringAfter("\"past\":[", "")
                .substringBefore("]")
            val entries = pastSection.split("},{")
            val lastEntry = entries.lastOrNull() ?: return null
            lastEntry.substringAfter("\"path\":\"").substringBefore("\"")
                .takeIf { it.startsWith("/") }
        } catch (_: Exception) { null }
    }

    fun latLngToTile(lat: Double, lng: Double, zoom: Int): Pair<Int, Int> {
        val n = 2.0.pow(zoom.toDouble())
        val x = ((lng + 180.0) / 360.0 * n).toInt()
        val latRad = lat * PI / 180.0
        val y = ((1.0 - ln(tan(latRad) + 1.0 / cos(latRad)) / PI) / 2.0 * n).toInt()
        return Pair(x, y)
    }
}
