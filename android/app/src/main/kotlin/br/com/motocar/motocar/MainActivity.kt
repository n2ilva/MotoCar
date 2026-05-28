package br.com.motocar.motocar

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import org.json.JSONArray
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val commands = "br.com.motocar/monitor_commands"
    private val events = "br.com.motocar/monitor_events"
    private val captureRequest = 4201
    private var pendingResult: MethodChannel.Result? = null
    private var eventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private val offerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == ScreenCaptureService.ACTION_CLOSE_APP) {
                finishAndRemoveTask()
                return
            }
            val rawText = intent?.getStringExtra(ScreenCaptureService.EXTRA_RAW_TEXT) ?: return
            val eventType = intent.getStringExtra("eventType") ?: "detected"
            acknowledgePending(eventType, rawText)
            eventSink?.success(mapOf("eventType" to eventType, "rawText" to rawText))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, commands)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startMonitoring" -> startMonitoring(result)
                    "stopMonitoring" -> {
                        stopService(Intent(this, ScreenCaptureService::class.java))
                        result.success(null)
                    }
                    "isRunning" -> result.success(ScreenCaptureService.running)
                    "updateSettings" -> {
                        getSharedPreferences(ScreenCaptureService.PREFS, MODE_PRIVATE).edit()
                            .putFloat("maxPickupKm", (call.argument<Double>("maxPickupKm") ?: 3.0).toFloat())
                            .putFloat("maxDestinationKm", (call.argument<Double>("maxDestinationKm") ?: 50.0).toFloat())
                            .putFloat("minimumFarePerKm", (call.argument<Double>("minimumFarePerKm") ?: 2.0).toFloat())
                            .apply()
                        result.success(null)
                    }
                    "pendingOffers" -> {
                        val prefs = getSharedPreferences(ScreenCaptureService.PREFS, MODE_PRIVATE)
                        val pending = JSONArray(prefs.getString("pending", "[]"))
                        val values = (0 until pending.length()).map {
                            val item = pending.getJSONObject(it)
                            mapOf(
                                "eventType" to item.optString("eventType", "detected"),
                                "rawText" to item.getString("rawText")
                            )
                        }
                        prefs.edit().putString("pending", "[]").apply()
                        result.success(values)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, events)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    registerOfferReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterOfferReceiver()
                }
            })
    }

    private fun startMonitoring(result: MethodChannel.Result) {
        if (!Settings.canDrawOverlays(this)) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
            result.success(false)
            return
        }
        pendingResult = result
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(manager.createScreenCaptureIntent(), captureRequest)
    }

    override fun onResume() {
        super.onResume()
        setMonitorAppVisible(true)
    }

    override fun onPause() {
        setMonitorAppVisible(false)
        super.onPause()
    }

    private fun setMonitorAppVisible(visible: Boolean) {
        if (!ScreenCaptureService.running) return
        startService(
            Intent(this, ScreenCaptureService::class.java)
                .putExtra(ScreenCaptureService.EXTRA_APP_VISIBLE, visible)
        )
    }

    @Deprecated("MediaProjection still returns through the Activity result contract.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != captureRequest) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult?.success(false)
            pendingResult = null
            return
        }
        val service = Intent(this, ScreenCaptureService::class.java)
            .putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
            .putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
            .putExtra(ScreenCaptureService.EXTRA_APP_VISIBLE, true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(service)
        else startService(service)
        pendingResult?.success(true)
        pendingResult = null
    }

    private fun registerOfferReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(ScreenCaptureService.ACTION_OFFER)
            addAction(ScreenCaptureService.ACTION_CLOSE_APP)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(offerReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(offerReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun unregisterOfferReceiver() {
        if (!receiverRegistered) return
        unregisterReceiver(offerReceiver)
        receiverRegistered = false
    }

    private fun acknowledgePending(eventType: String, rawText: String) {
        val prefs = getSharedPreferences(ScreenCaptureService.PREFS, MODE_PRIVATE)
        val pending = JSONArray(prefs.getString("pending", "[]"))
        val remaining = JSONArray()
        var removed = false
        for (index in 0 until pending.length()) {
            val item = pending.getJSONObject(index)
            if (!removed &&
                item.optString("eventType", "detected") == eventType &&
                item.optString("rawText") == rawText
            ) {
                removed = true
            } else {
                remaining.put(item)
            }
        }
        prefs.edit().putString("pending", remaining.toString()).apply()
    }

    override fun onDestroy() {
        unregisterOfferReceiver()
        super.onDestroy()
    }
}
