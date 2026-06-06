package com.airbridge.device

import android.app.ActivityManager
import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import android.content.Intent
import android.content.IntentFilter
import com.airbridge.protocol.DeviceInfo

/**
 * Czy dany status baterii (EXTRA_STATUS z ACTION_BATTERY_CHANGED) oznacza ładowanie.
 * Używamy statusu z broadcastu, bo `BatteryManager.isCharging` bywa niewiarygodne
 * na niektórych urządzeniach (np. Samsung zwraca false mimo statusu CHARGING).
 */
internal fun batteryStatusIsCharging(status: Int): Boolean =
    status == BatteryManager.BATTERY_STATUS_CHARGING ||
    status == BatteryManager.BATTERY_STATUS_FULL

/**
 * Collects device hardware/OS info for the macOS Home screen: exact (user-set)
 * name, storage, RAM, battery. Read-only; no special permissions needed.
 */
object DeviceInfoProvider {
    fun collect(context: Context): DeviceInfo {
        val name = exactName(context)

        // Internal data partition — what users think of as "phone storage".
        val stat = StatFs(Environment.getDataDirectory().path)
        val totalStorage = stat.blockCountLong * stat.blockSizeLong
        val freeStorage = stat.availableBlocksLong * stat.blockSizeLong

        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mem)

        val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val battery = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

        // Stan ładowania ze sticky broadcastu (źródło prawdy zgodne z systemowym UI);
        // BatteryManager.isCharging bywa zawodne (Samsung zwraca false mimo CHARGING).
        val batteryStatus = context
            .registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)
            ?: BatteryManager.BATTERY_STATUS_UNKNOWN
        val charging = batteryStatusIsCharging(batteryStatus)
        val chargeTimeMs: Long =
            if (charging && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                // computeChargeTimeRemaining(): ms do pełna, lub -1 gdy nieznany.
                bm.computeChargeTimeRemaining()
            } else {
                -1L
            }

        return DeviceInfo(
            name = name,
            model = Build.MODEL,
            manufacturer = Build.MANUFACTURER.replaceFirstChar { it.uppercase() },
            androidVersion = Build.VERSION.RELEASE,
            sdkInt = Build.VERSION.SDK_INT,
            totalStorageBytes = totalStorage,
            freeStorageBytes = freeStorage,
            totalRamBytes = mem.totalMem,
            freeRamBytes = mem.availMem,
            batteryPercent = battery,
            batteryCharging = charging,
            chargeTimeRemainingMs = chargeTimeMs
        )
    }

    /**
     * The user-set device name (Settings → About → Device name) is usually the
     * marketing name ("Galaxy Z Fold7"), far friendlier than the Build.MODEL
     * codename. Fall back to manufacturer + model when unavailable.
     */
    private fun exactName(context: Context): String {
        // Settings.Global "device_name" is the user-set name (usually the
        // marketing name). Reading other settings like Secure "bluetooth_name"
        // throws SecurityException on newer Android, so don't.
        val global = runCatching {
            Settings.Global.getString(context.contentResolver, "device_name")
        }.getOrNull()
        return global?.takeIf { it.isNotBlank() }
            ?: "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}"
    }
}
