package ar.com.consultoradiagonales.condienlaruta

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer

/**
 * Renderiza el mapa base (OpenStreetMap) + overlay del radar meteorológico
 * sobre la Surface de Android Auto.
 */
class SurfaceRenderer : SurfaceCallback {

    private var surfaceContainer: SurfaceContainer? = null
    private var radarBitmap: Bitmap? = null
    private val tileRenderer = MapTileRenderer()

    private val positionPaint = Paint().apply {
        color = Color.rgb(0, 100, 220)
        style = Paint.Style.FILL
        isAntiAlias = true
    }
    private val positionRingPaint = Paint().apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 5f
        isAntiAlias = true
    }
    private val radarPaint = Paint().apply {
        alpha = 155  // radar semi-transparente sobre el mapa
    }

    override fun onSurfaceAvailable(holder: SurfaceContainer) {
        surfaceContainer = holder
        redraw()
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        redraw()
    }

    override fun onSurfaceDestroyed(holder: SurfaceContainer) {
        surfaceContainer = null
    }

    fun updateRadar(result: WeatherResult) {
        radarBitmap = result.radarBitmap
        redraw()
    }

    private fun redraw() {
        val container = surfaceContainer ?: return
        val surface = container.surface ?: return
        if (!surface.isValid) return

        val canvas: Canvas = surface.lockCanvas(null) ?: return
        try {
            drawFrame(canvas)
        } finally {
            surface.unlockCanvasAndPost(canvas)
        }
    }

    private fun drawFrame(canvas: Canvas) {
        val lat = LocationRepository.currentLat
        val lng = LocationRepository.currentLng
        val zoom = 10  // zoom fijo "ver el camino que viene"

        // 1. Mapa base OpenStreetMap
        tileRenderer.draw(canvas, lat, lng, zoom)

        // 2. Overlay radar (semi-transparente encima del mapa)
        radarBitmap?.let { bmp ->
            val scaled = Bitmap.createScaledBitmap(bmp, canvas.width, canvas.height, true)
            canvas.drawBitmap(scaled, 0f, 0f, radarPaint)
        }

        // 3. Punto de posición actual en el centro
        val cx = canvas.width / 2f
        val cy = canvas.height / 2f
        canvas.drawCircle(cx, cy, 20f, positionPaint)
        canvas.drawCircle(cx, cy, 20f, positionRingPaint)
    }
}
