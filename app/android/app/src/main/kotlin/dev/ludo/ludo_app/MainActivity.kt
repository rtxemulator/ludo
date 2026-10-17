package dev.ludo.ludo_app

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and a tiny haptics channel (no plugin): pulses go
 * straight to [Vibrator] so they work even when system "touch feedback" is
 * off, and so tick / click / heavy and their strength can be expressed.
 *
 * Dart side: app/lib/haptics/haptics_service.dart. Patterns live in
 * lib/ui/core/haptics.dart; this class only plays one pulse at a time.
 */
class MainActivity : FlutterActivity() {
    private var vibrator: Vibrator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        vibrator = resolveVibrator()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pulse" -> {
                        val kind = call.argument<String>("kind") ?: "tick"
                        val strength = call.argument<Double>("strength") ?: 1.0
                        result.success(pulse(kind, strength))
                    }
                    "isAvailable" -> result.success(vibrator?.hasVibrator() == true)
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun resolveVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager =
                getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    /** Returns true if a vibration was started. */
    @Suppress("DEPRECATION")
    private fun pulse(kind: String, strength: Double): Boolean {
        val v = vibrator ?: return false
        if (!v.hasVibrator()) return false
        val s = strength.coerceIn(0.0, 1.0)
        val durationMs: Long = when (kind) {
            "heavy" -> 40L
            "click" -> 22L
            else -> 12L
        }
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val hasAmplitude = v.hasAmplitudeControl()
                val fullStrength = s >= 0.95
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                    (fullStrength || !hasAmplitude)
                ) {
                    val effectId = when (kind) {
                        "heavy" -> VibrationEffect.EFFECT_HEAVY_CLICK
                        "click" -> VibrationEffect.EFFECT_CLICK
                        else -> VibrationEffect.EFFECT_TICK
                    }
                    v.vibrate(VibrationEffect.createPredefined(effectId))
                } else {
                    val amplitude = if (hasAmplitude) {
                        (s * 255).toInt().coerceIn(1, 255)
                    } else {
                        VibrationEffect.DEFAULT_AMPLITUDE
                    }
                    v.vibrate(VibrationEffect.createOneShot(durationMs, amplitude))
                }
            } else {
                v.vibrate(durationMs)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        private const val CHANNEL = "dev.ludo/haptics"
    }
}
