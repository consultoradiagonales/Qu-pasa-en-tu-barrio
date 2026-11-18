package ar.com.consultoradiagonales.condienlaruta

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.tan

/**
 * Descarga y dibuja tiles de OpenStreetMap sobre el Canvas de Android Auto.
 * OSM es gratuito y no requiere API key.
 * Política de uso: https://operations.osmfoundation.org/policies/tiles/
 */
class MapTileRenderer {

    private val client = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    // Cache en memoria de tiles descargados (key = "zoom/x/y")
    private val tileCache = LinkedHashMap<String, Bitmap>(64, 0.75f, true)
    private val maxCacheSize = 50

    fun draw(canvas: Canvas, lat: Double, lng: Double, zoom: Int) {
        val (centerX, centerY) = latLngToTile(lat, lng, zoom)
        val tileSize = canvas.width / 3  // grilla 3×3

        // Dibuja los 9 tiles alrededor de la posición actual
        for (dy in -1..1) {
            for (dx in -1..1) {
                val tx = centerX + dx
                val ty = centerY + dy
                val bitmap = getTileCached(zoom, tx, ty) ?: continue
                val left = (dx + 1) * tileSize
                val top = (dy + 1) * tileSize
                val scaled = Bitmap.createScaledBitmap(bitmap, tileSize, tileSize, true)
                canvas.drawBitmap(scaled, left.toFloat(), top.toFloat(), Paint())
            }
        }
    }

    private fun getTileCached(zoom: Int, x: Int, y: Int): Bitmap? {
        val key = "$zoom/$x/$y"
        tileCache[key]?.let { return it }
        return fetchTile(zoom, x, y)?.also { bmp ->
            if (tileCache.size >= maxCacheSize) {
                tileCache.remove(tileCache.keys.first())
            }
            tileCache[key] = bmp
        }
    }

    private fun fetchTile(zoom: Int, x: Int, y: Int): Bitmap? {
        val url = "https://tile.openstreetmap.org/$zoom/$x/$y.png"
        return try {
            val response = client.newCall(
                Request.Builder()
                    .url(url)
                    .header("User-Agent", "ConDiEnLaRuta/1.0 (ar.com.consultoradiagonales.condienlaruta)")
                    .build()
            ).execute()
            BitmapFactory.decodeStream(response.body?.byteStream())
        } catch (_: Exception) { null }
    }

    private fun latLngToTile(lat: Double, lng: Double, zoom: Int): Pair<Int, Int> {
        val n = 2.0.pow(zoom.toDouble())
        val x = ((lng + 180.0) / 360.0 * n).toInt()
        val latRad = lat * PI / 180.0
        val y = ((1.0 - ln(tan(latRad) + 1.0 / cos(latRad)) / PI) / 2.0 * n).toInt()
        return Pair(x, y)
    }
}
