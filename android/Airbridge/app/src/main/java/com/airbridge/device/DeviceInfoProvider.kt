package com.airbridge.device

import android.app.ActivityManager
import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import com.airbridge.protocol.DeviceInfo

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
            batteryPercent = battery
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
