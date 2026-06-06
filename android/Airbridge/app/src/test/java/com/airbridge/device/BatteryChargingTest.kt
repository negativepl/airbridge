package com.airbridge.device

import android.os.BatteryManager
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BatteryChargingTest {
    @Test fun chargingStatusIsCharging() {
        assertTrue(batteryStatusIsCharging(BatteryManager.BATTERY_STATUS_CHARGING))
    }

    @Test fun fullCountsAsCharging() {
        assertTrue(batteryStatusIsCharging(BatteryManager.BATTERY_STATUS_FULL))
    }

    @Test fun dischargingNotCharging() {
        assertFalse(batteryStatusIsCharging(BatteryManager.BATTERY_STATUS_DISCHARGING))
    }

    @Test fun notChargingNotCharging() {
        assertFalse(batteryStatusIsCharging(BatteryManager.BATTERY_STATUS_NOT_CHARGING))
    }

    @Test fun unknownNotCharging() {
        assertFalse(batteryStatusIsCharging(BatteryManager.BATTERY_STATUS_UNKNOWN))
    }
}
