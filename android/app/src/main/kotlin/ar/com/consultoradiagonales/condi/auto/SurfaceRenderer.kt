package ar.com.consultoradiagonales.condi.auto

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import androidx.car.app.CarContext
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer

class SurfaceRenderer(private val carContext: CarContext) : SurfaceCallback {

    private var surface: android.view.Surface? = null
    private var visibleArea: Rect? = null
    private val tileRenderer = MapTileRenderer()
    private var radarBitmap: Bitmap? = null
    private val radarPaint = Paint().apply { alpha = 155 }

    fun updateRadar(bitmap: Bitmap?) {
        radarBitmap = bitmap
        render()
    }

    override fun onSurfaceAvailable(container: SurfaceContainer) {
        surface = container.surface
        render()
    }

    override fun onVisibleAreaChanged(area: Rect) {
        visibleArea = area
        render()
    }

    override fun onSurfaceDestroyed(container: SurfaceContainer) {
        surface = null
    }

    private fun render() {
        val s = surface ?: return
        try {
            val canvas: Canvas = s.lockCanvas(null) ?: return
            canvas.drawColor(Color.DKGRAY)

            tileRenderer.draw(canvas, LocationRepository.currentLat, LocationRepository.currentLng, zoom = 13)

            radarBitmap?.let { radar ->
                val scaled = Bitmap.createScaledBitmap(radar, canvas.width, canvas.height, true)
                canvas.drawBitmap(scaled, 0f, 0f, radarPaint)
            }

            val cx = canvas.width / 2f
            val cy = canvas.height / 2f
            canvas.drawCircle(cx, cy, 18f, Paint().apply { color = Color.parseColor("#0064DC"); style = Paint.Style.FILL })
            canvas.drawCircle(cx, cy, 18f, Paint().apply { color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 3f })

            s.unlockCanvasAndPost(canvas)
        } catch (_: Exception) {}
    }
}
