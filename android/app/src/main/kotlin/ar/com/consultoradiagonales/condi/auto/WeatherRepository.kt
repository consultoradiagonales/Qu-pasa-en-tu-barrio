package ar.com.consultoradiagonales.condi.auto

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.tan

data class WeatherResult(val radarBitmap: Bitmap?, val alertText: String?)

class WeatherRepository {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    fun fetchRadarAndAlerts(lat: Double, lng: Double): WeatherResult {
        return try {
            val radarPath = fetchLatestRadarPath() ?: return WeatherResult(null, null)
            val zoom = 7
            val (tx, ty) = latLngToTile(lat, lng, zoom)
            val tileUrl = "https://tilecache.rainviewer.com${radarPath}/256/$zoom/$tx/$ty/2/1_1.png"

            val bitmap = fetchBitmap(tileUrl)
            val alert = if (bitmap != null && hasIntenseRain(bitmap)) {
                "⚠️ Lluvia intensa en la ruta"
            } else null

            WeatherResult(bitmap, alert)
        } catch (_: Exception) {
            WeatherResult(null, null)
        }
    }

    private fun fetchLatestRadarPath(): String? {
        val response = client.newCall(
            Request.Builder().url("https://api.rainviewer.com/public/weather-maps.json").build()
        ).execute()
        val body = response.body?.string() ?: return null
        val json = JSONObject(body)
        val radar = json.getJSONObject("radar")
        val past = radar.getJSONArray("past")
        val latest = past.getJSONObject(past.length() - 1)
        return latest.getString("path")
    }

    private fun fetchBitmap(url: String): Bitmap? {
        val response = client.newCall(Request.Builder().url(url).build()).execute()
        return BitmapFactory.decodeStream(response.body?.byteStream())
    }

    private fun hasIntenseRain(bitmap: Bitmap): Boolean {
        val w = bitmap.width; val h = bitmap.height
        for (y in 0 until h step 4) {
            for (x in 0 until w step 4) {
                val px = bitmap.getPixel(x, y)
                val r = android.graphics.Color.red(px)
                val g = android.graphics.Color.green(px)
                val a = android.graphics.Color.alpha(px)
                if (r > 150 && g < 80 && a > 100) return true
            }
        }
        return false
    }

    private fun latLngToTile(lat: Double, lng: Double, zoom: Int): Pair<Int, Int> {
        val n = 2.0.pow(zoom.toDouble())
        val x = ((lng + 180.0) / 360.0 * n).toInt()
        val latRad = lat * PI / 180.0
        val y = ((1.0 - ln(tan(latRad) + 1.0 / cos(latRad)) / PI) / 2.0 * n).toInt()
        return Pair(x, y)
    }
}
