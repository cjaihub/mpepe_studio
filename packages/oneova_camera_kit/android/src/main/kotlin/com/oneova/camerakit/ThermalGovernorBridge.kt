package com.oneova.camerakit

import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.PerformanceHintManager
import android.os.PowerManager

/**
 * Android thermal governor bridge.
 * Uses Android ADPF (PowerManager.getThermalHeadroom forecast + PerformanceHintManager sessions)
 * and battery saver states.
 */
class ThermalGovernorBridge(private val context: Context) {

    private val powerManager: PowerManager? =
        context.getSystemService(Context.POWER_SERVICE) as? PowerManager

    private val batteryManager: BatteryManager? =
        context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager

    private val performanceHintManager: PerformanceHintManager? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(Context.PERFORMANCE_HINT_SERVICE) as? PerformanceHintManager
        } else {
            null
        }

    private var activeHintSession: Any? = null

    fun getThermalHeadroom(forecastSeconds: Int): Float {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && powerManager != null) {
            return try {
                val clamped = forecastSeconds.coerceIn(0, 60)
                powerManager.getThermalHeadroom(clamped)
            } catch (_: Exception) {
                0.5f
            }
        }
        return 0.5f
    }

    fun getThermalSnapshot(): Map<String, Any?> {
        val headroom = getThermalHeadroom(0)
        val forecast10s = getThermalHeadroom(10)
        val isPowerSave = powerManager?.isPowerSaveMode ?: false

        val batteryLevel = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
        val isCharging = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && batteryManager != null) {
            batteryManager.isCharging
        } else {
            false
        }

        // Map headroom to normalized thermal level (nominal, fair, serious, critical)
        val thermalLevel = when {
            headroom >= 1.2f -> "critical"
            headroom >= 0.95f -> "serious"
            headroom >= 0.75f -> "fair"
            else -> "nominal"
        }

        return mapOf(
            "headroom" to headroom,
            "forecastHeadroom10s" to forecast10s,
            "thermalLevel" to thermalLevel,
            "isPowerSaveMode" to isPowerSave,
            "batteryLevel" to batteryLevel,
            "isCharging" to isCharging,
            "timestamp" to System.currentTimeMillis()
        )
    }

    fun createHintSession(targetDurationNanos: Long): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && performanceHintManager != null) {
            try {
                closeHintSession()
                val threadIds = intArrayOf(android.os.Process.myTid())
                activeHintSession = performanceHintManager.createHintSession(threadIds, targetDurationNanos)
                return activeHintSession != null
            } catch (_: Exception) {}
        }
        return false
    }

    fun reportActualDuration(actualDurationNanos: Long): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val session = activeHintSession as? PerformanceHintManager.Session
            if (session != null) {
                try {
                    session.reportActualWorkDuration(actualDurationNanos)
                    return true
                } catch (_: Exception) {}
            }
        }
        return false
    }

    fun closeHintSession() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val session = activeHintSession as? PerformanceHintManager.Session
            session?.close()
            activeHintSession = null
        }
    }
}
