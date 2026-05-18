package com.example.antenna_aligner

import android.hardware.GeomagneticField
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.antenna_aligner/geomagnetic"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getDeclination") {
                val lat = call.argument<Double>("lat")?.toFloat()
                val lon = call.argument<Double>("lon")?.toFloat()
                val alt = call.argument<Double>("alt")?.toFloat()
                val timeMillis = call.argument<Long>("time") ?: System.currentTimeMillis()

                if (lat != null && lon != null && alt != null) {
                    val geomagneticField = GeomagneticField(lat, lon, alt, timeMillis)
                    result.success(geomagneticField.declination.toDouble())
                } else {
                    result.error("INVALID_ARGUMENTS", "Latitude, longitude, or altitude is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
