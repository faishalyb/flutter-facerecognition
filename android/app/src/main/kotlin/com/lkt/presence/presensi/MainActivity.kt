package com.lkt.presence.presensi

import android.graphics.Rect
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val channelName = "spoof_detector"
    private val executor = Executors.newSingleThreadExecutor()
    private var spoof: FaceSpoofDetectorNative? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        spoof = FaceSpoofDetectorNative(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectSpoof" -> {
                        val imagePath = call.argument<String>("imagePath")!!
                        val left = call.argument<Int>("left")!!
                        val top = call.argument<Int>("top")!!
                        val right = call.argument<Int>("right")!!
                        val bottom = call.argument<Int>("bottom")!!

                        executor.execute {
                            try {
                                val rect = Rect(left, top, right, bottom)
                                val r = spoof!!.detectSpoof(imagePath, rect)
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "isSpoof" to r.isSpoof,
                                            "score" to r.score.toDouble(),
                                            "timeMillis" to r.timeMillis
                                        )
                                    )
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("SPOOF_ERR", e.message, null)
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        spoof?.close()
        spoof = null
        executor.shutdown()
        super.onDestroy()
    }
}
