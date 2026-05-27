package br.com.motocar.motocar

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.pm.ServiceInfo
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ScreenCaptureService : Service(), LocationListener {
    companion object {
        const val PREFS = "motocar_monitor"
        const val ACTION_OFFER = "br.com.motocar.NEW_OFFER"
        const val ACTION_CLOSE_APP = "br.com.motocar.CLOSE_APP"
        const val EXTRA_RAW_TEXT = "rawText"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_LOCATION_ENABLED = "locationEnabled"
        const val EXTRA_APP_VISIBLE = "appVisible"
        var running: Boolean = false
            private set
    }

    private val handler = Handler(Looper.getMainLooper())
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private lateinit var windowManager: WindowManager
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var popup: View? = null
    private var trackingFab: TextView? = null
    private var closeTarget: TextView? = null
    private var locationManager: LocationManager? = null
    private var locationForegroundEnabled = false
    private var trackingSessionId: Long? = null
    private var trackingDistanceKm = 0.0
    private var lastLocation: Location? = null
    private var activeAcceptedRawText: String? = null
    private var appVisible = false
    private var processing = false
    private var lastFrameAt = 0L
    private var lastFingerprint = ""
    private var lastOfferAt = 0L

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        updateForegroundType(includeLocation = false)
        showTrackingFab()
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.hasExtra(EXTRA_APP_VISIBLE) == true) {
            appVisible = intent.getBooleanExtra(EXTRA_APP_VISIBLE, false)
            if (appVisible) removeOfferPopup()
            if (projection != null) return START_NOT_STICKY
        }
        if (projection != null) return START_NOT_STICKY
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: return START_NOT_STICKY
        if (intent.getBooleanExtra(EXTRA_LOCATION_ENABLED, false)) {
            locationForegroundEnabled = true
            updateForegroundType(includeLocation = true)
        }
        @Suppress("DEPRECATION")
        val resultData = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        } ?: return START_NOT_STICKY
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projection = manager.getMediaProjection(resultCode, resultData)
        projection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stopSelf()
            }
        }, handler)
        beginCapture()
        return START_NOT_STICKY
    }

    private fun beginCapture() {
        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        virtualDisplay = projection?.createVirtualDisplay(
            "MotoCarCapture",
            width,
            height,
            metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null,
            handler
        )
        imageReader?.setOnImageAvailableListener({ reader ->
            val now = System.currentTimeMillis()
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            if (appVisible || processing || now - lastFrameAt < 650) {
                image.close()
                return@setOnImageAvailableListener
            }
            lastFrameAt = now
            val plane = image.planes[0]
            val bitmapWidth = width + (plane.rowStride - plane.pixelStride * width) / plane.pixelStride
            val bitmap = Bitmap.createBitmap(bitmapWidth, height, Bitmap.Config.ARGB_8888)
            bitmap.copyPixelsFromBuffer(plane.buffer)
            image.close()
            val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
            if (cropped !== bitmap) bitmap.recycle()
            processFrame(cropped)
        }, handler)
    }

    private fun processFrame(bitmap: Bitmap) {
        processing = true
        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { result ->
                if (appVisible) {
                    return@addOnSuccessListener
                }
                if (activeAcceptedRawText != null && detectsCompletedRide(result.text)) {
                    stopFloatingTracking(markCompleted = true)
                } else {
                    parseOffer(result.text)?.let(::handleOffer)
                }
            }
            .addOnCompleteListener {
                bitmap.recycle()
                processing = false
            }
    }

    private fun parseOffer(rawText: String): DetectedOffer? {
        val normalised = rawText.lowercase(Locale("pt", "BR"))
        val platform = when {
            normalised.contains("uber") -> "Uber"
            Regex("""(^|\D)99(\D|$)""").containsMatchIn(normalised) ||
                normalised.contains("99pop") -> "99"
            else -> return null
        }
        val fareText = Regex("""r\$\s*(\d+(?:[.,]\d{2})?)""", RegexOption.IGNORE_CASE)
            .find(normalised)?.groupValues?.get(1) ?: return null
        val distances = Regex("""(\d+(?:[.,]\d+)?)\s*km""", RegexOption.IGNORE_CASE)
            .findAll(normalised).map { decimal(it.groupValues[1]) }.toList()
        if (distances.size < 2) return null
        val fare = decimal(fareText)
        val pickup = distances[0]
        val destination = distances[1]
        if (fare <= 0 || destination <= 0) return null
        return DetectedOffer(platform, fare, pickup, destination, rawText)
    }

    private fun decimal(value: String): Double {
        val canonical = if (value.contains(',')) {
            value.replace(".", "").replace(',', '.')
        } else value
        return canonical.toDoubleOrNull() ?: 0.0
    }

    private fun handleOffer(offer: DetectedOffer) {
        val now = System.currentTimeMillis()
        val fingerprint = "${offer.platform}:${offer.fare}:${offer.pickup}:${offer.destination}"
        if (fingerprint == lastFingerprint && now - lastOfferAt < 12000) return
        lastFingerprint = fingerprint
        lastOfferAt = now
        sendOfferEvent("detected", offer.rawText)
        showPopup(offer)
    }

    private fun showPopup(offer: DetectedOffer) {
        removeOfferPopup()
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val worthIt = offer.pickup <= prefs.getFloat("maxPickupKm", 3f) &&
            offer.destination <= prefs.getFloat("maxDestinationKm", 50f) &&
            offer.perKm >= prefs.getFloat("minimumFarePerKm", 2f)
        val color = if (worthIt) Color.rgb(15, 120, 65) else Color.rgb(175, 35, 43)
        val summary = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 12f
            setPadding(dp(14), dp(10), dp(14), 0)
            this.text = "${offer.platform} | R$ ${format(offer.fare)} | " +
                "Busca ${format(offer.pickup)} km | Destino ${format(offer.destination)} km"
        }
        val perKm = TextView(this).apply {
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 27f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(dp(14), dp(2), dp(14), dp(5))
            text = "R$ ${format(offer.perKm)}/km"
        }
        val status = TextView(this).apply {
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            textSize = 11f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding(dp(14), 0, dp(14), dp(5))
            text = if (worthIt) "VALE A PENA" else "FORA DO LIMITE"
        }
        val accept = Button(this).apply {
            text = "ACEITEI - INICIAR TRAJETO"
            setOnClickListener { handleAcceptedOffer(offer) }
        }
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color)
            addView(summary)
            addView(perKm)
            addView(status)
            addView(accept)
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = 100
        }
        windowManager.addView(container, params)
        popup = container
        handler.postDelayed({
            if (popup === container) {
                windowManager.removeView(container)
                popup = null
            }
        }, 6500)
    }

    private fun handleAcceptedOffer(offer: DetectedOffer) {
        activeAcceptedRawText = offer.rawText
        sendOfferEvent("accepted", offer.rawText)
        removeOfferPopup()
        if (trackingSessionId == null) startFloatingTracking()
    }

    private fun detectsCompletedRide(rawText: String): Boolean {
        val normalised = rawText.lowercase(Locale("pt", "BR"))
        return listOf(
            "viagem concluida",
            "corrida concluida",
            "corrida finalizada",
            "resumo da viagem",
            "resumo da corrida"
        ).any(normalised::contains)
    }

    private fun showTrackingFab() {
        val size = dp(68)
        val button = TextView(this).apply {
            gravity = Gravity.CENTER
            text = "PLAY\nTRAJETO"
            textSize = 10f
            setTextColor(Color.WHITE)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            background = fabBackground(Color.rgb(18, 107, 83))
        }
        val metrics = resources.displayMetrics
        val params = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = metrics.widthPixels - size - dp(14)
            y = metrics.heightPixels - size - dp(92)
        }
        enableFabDrag(button, params)
        windowManager.addView(button, params)
        trackingFab = button
    }

    private fun fabBackground(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
        setStroke(dp(2), Color.WHITE)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    private fun enableFabDrag(
        button: TextView,
        params: WindowManager.LayoutParams
    ) {
        val touchSlop = ViewConfiguration.get(this).scaledTouchSlop
        var startRawX = 0f
        var startRawY = 0f
        var startX = 0
        var startY = 0
        var dragging = false
        button.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startRawX = event.rawX
                    startRawY = event.rawY
                    startX = params.x
                    startY = params.y
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - startRawX
                    val dy = event.rawY - startRawY
                    if (!dragging &&
                        (kotlin.math.abs(dx) > touchSlop ||
                            kotlin.math.abs(dy) > touchSlop)
                    ) {
                        dragging = true
                        showCloseTarget()
                    }
                    if (dragging) {
                        val metrics = resources.displayMetrics
                        params.x = (startX + dx.toInt()).coerceIn(
                            0,
                            metrics.widthPixels - button.width
                        )
                        params.y = (startY + dy.toInt()).coerceIn(
                            0,
                            metrics.heightPixels - button.height
                        )
                        windowManager.updateViewLayout(button, params)
                        highlightCloseTarget(isOverCloseTarget(button, params))
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (dragging) {
                        val close = isOverCloseTarget(button, params)
                        hideCloseTarget()
                        if (close) shutdownMonitoring()
                    } else {
                        toggleFloatingTracking()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    hideCloseTarget()
                    true
                }
                else -> false
            }
        }
    }

    private fun showCloseTarget() {
        if (closeTarget != null) return
        val size = dp(76)
        val target = TextView(this).apply {
            gravity = Gravity.CENTER
            text = "X"
            textSize = 30f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = fabBackground(Color.rgb(166, 32, 39))
        }
        val params = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(22)
        }
        windowManager.addView(target, params)
        closeTarget = target
    }

    private fun highlightCloseTarget(highlight: Boolean) {
        closeTarget?.background = fabBackground(
            if (highlight) Color.rgb(235, 35, 45) else Color.rgb(166, 32, 39)
        )
    }

    private fun hideCloseTarget() {
        closeTarget?.let(windowManager::removeView)
        closeTarget = null
    }

    private fun isOverCloseTarget(
        button: View,
        params: WindowManager.LayoutParams
    ): Boolean {
        val metrics = resources.displayMetrics
        val buttonCenterX = params.x + button.width / 2f
        val buttonCenterY = params.y + button.height / 2f
        val targetCenterX = metrics.widthPixels / 2f
        val targetCenterY = metrics.heightPixels - dp(22) - dp(38f)
        val dx = buttonCenterX - targetCenterX
        val dy = buttonCenterY - targetCenterY
        return dx * dx + dy * dy <= dp(70f) * dp(70f)
    }

    private fun dp(value: Float) = value * resources.displayMetrics.density

    private fun shutdownMonitoring() {
        hideCloseTarget()
        if (trackingSessionId != null) stopFloatingTracking()
        sendBroadcast(Intent(ACTION_CLOSE_APP).setPackage(packageName))
        stopSelf()
    }

    private fun removeOfferPopup() {
        popup?.let(windowManager::removeView)
        popup = null
    }

    private fun toggleFloatingTracking() {
        if (trackingSessionId == null) {
            startFloatingTracking()
        } else {
            stopFloatingTracking(markCompleted = activeAcceptedRawText != null)
        }
    }

    private fun startFloatingTracking() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Toast.makeText(
                this,
                "Autorize localizacao no MotoCar antes de medir o trajeto.",
                Toast.LENGTH_LONG
            ).show()
            return
        }
        if (!locationForegroundEnabled) {
            Toast.makeText(
                this,
                "Autorize localizacao e reinicie a leitura para usar o trajeto.",
                Toast.LENGTH_LONG
            ).show()
            return
        }
        trackingDistanceKm = 0.0
        lastLocation = null
        val values = ContentValues().apply {
            put("started_at", timestamp())
            putNull("finished_at")
            put("distance_km", 0.0)
        }
        trackingSessionId = openOrCreateDatabase("motocar.db", MODE_PRIVATE, null).use {
            it.insert("tracking_sessions", null, values)
        }
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        try {
            locationManager?.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000L,
                10f,
                this
            )
            locationManager?.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER,
                2000L,
                10f,
                this
            )
        } catch (_: SecurityException) {
            stopFloatingTracking()
            return
        }
        updateTrackingFab()
    }

    private fun stopFloatingTracking(markCompleted: Boolean = false) {
        locationManager?.removeUpdates(this)
        locationManager = null
        trackingSessionId?.let { id ->
            val values = ContentValues().apply {
                put("finished_at", timestamp())
                put("distance_km", trackingDistanceKm)
            }
            openOrCreateDatabase("motocar.db", MODE_PRIVATE, null).use {
                it.update("tracking_sessions", values, "id = ?", arrayOf(id.toString()))
            }
        }
        trackingSessionId = null
        lastLocation = null
        if (markCompleted) {
            activeAcceptedRawText?.let { sendOfferEvent("completed", it) }
            activeAcceptedRawText = null
        }
        updateTrackingFab()
    }

    override fun onLocationChanged(location: Location) {
        lastLocation?.let { previous ->
            trackingDistanceKm += previous.distanceTo(location) / 1000.0
        }
        lastLocation = location
        trackingSessionId?.let { id ->
            val values = ContentValues().apply { put("distance_km", trackingDistanceKm) }
            openOrCreateDatabase("motocar.db", MODE_PRIVATE, null).use {
                it.update("tracking_sessions", values, "id = ?", arrayOf(id.toString()))
            }
        }
        updateTrackingFab()
    }

    private fun updateTrackingFab() {
        val active = trackingSessionId != null
        trackingFab?.apply {
            text = if (active) "PAUSE\n${format(trackingDistanceKm)} km" else "PLAY\nTRAJETO"
            background = fabBackground(
                if (active) Color.rgb(175, 35, 43) else Color.rgb(18, 107, 83)
            )
        }
    }

    private fun timestamp() =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(Date())

    private fun format(value: Double) = String.format(Locale("pt", "BR"), "%.2f", value)

    private fun sendOfferEvent(eventType: String, rawText: String) {
        storePending(eventType, rawText)
        sendBroadcast(
            Intent(ACTION_OFFER)
                .setPackage(packageName)
                .putExtra("eventType", eventType)
                .putExtra(EXTRA_RAW_TEXT, rawText)
        )
    }

    private fun storePending(eventType: String, rawText: String) {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val pending = JSONArray(prefs.getString("pending", "[]"))
        pending.put(
            JSONObject()
                .put("eventType", eventType)
                .put("rawText", rawText)
        )
        while (pending.length() > 100) pending.remove(0)
        prefs.edit().putString("pending", pending.toString()).apply()
    }

    private fun buildNotification(): android.app.Notification {
        val channelId = "screen_monitor"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Leitura de ofertas",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MotoCar analisando ofertas")
            .setContentText("Captura ativa para identificar Uber e 99")
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun updateForegroundType(includeLocation: Boolean) {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            if (includeLocation) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            startForeground(44, notification, types)
        } else {
            startForeground(44, notification)
        }
    }

    override fun onDestroy() {
        if (trackingSessionId != null) stopFloatingTracking()
        removeOfferPopup()
        trackingFab?.let(windowManager::removeView)
        hideCloseTarget()
        imageReader?.close()
        virtualDisplay?.release()
        projection?.stop()
        recognizer.close()
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private data class DetectedOffer(
        val platform: String,
        val fare: Double,
        val pickup: Double,
        val destination: Double,
        val rawText: String
    ) {
        val perKm: Double get() = fare / (pickup + destination)
    }
}
