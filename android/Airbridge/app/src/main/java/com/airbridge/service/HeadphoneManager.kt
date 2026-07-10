package com.airbridge.service

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat

/** Time window after a release during which the headphones' own auto-reconnect
 *  to this phone is rejected, so the Mac has a chance to grab them. */
private const val GUARD_MS = 15_000L

/** Pure, clock-injectable guard window — unit-tested in ReconnectGuardTest. */
class ReconnectGuard(private val clockMs: () -> Long) {
    private var until = Long.MIN_VALUE

    val isActive: Boolean get() = clockMs() < until

    fun arm(durationMs: Long) {
        until = clockMs() + durationMs
    }

    fun disarm() {
        until = Long.MIN_VALUE
    }
}

data class BondedDevice(val name: String, val address: String)

/**
 * Connects and disconnects the user-selected Bluetooth headphones on request
 * from the handoff flow. Uses the hidden BluetoothA2dp/BluetoothHeadset
 * connect()/disconnect() methods via reflection (greylisted, the same approach
 * long used by auto-connect utilities); every call is wrapped so a blocked API
 * degrades to a logged failure, never a crash.
 */
class HeadphoneManager(private val context: Context) {

    companion object {
        private const val TAG = "HeadphoneManager"
    }

    var selectedAddress: String? = null

    /** Fires on ACL connect/disconnect of the selected headphones. */
    var onStateChanged: ((connected: Boolean, address: String, name: String) -> Unit)? = null

    private var a2dp: BluetoothProfile? = null
    private var headset: BluetoothProfile? = null
    private val guard = ReconnectGuard { SystemClock.elapsedRealtime() }
    private var receiverRegistered = false

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED

    private val profileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            when (profile) {
                BluetoothProfile.A2DP -> a2dp = proxy
                BluetoothProfile.HEADSET -> headset = proxy
            }
            // Profile proxies bind asynchronously after start(); a caller that
            // queries isConnected() right after start() can observe a false
            // "disconnected" even though the headphones are already linked.
            // Catch up here once this proxy's connected-device list is available.
            reportIfAlreadyConnected(proxy)
        }

        override fun onServiceDisconnected(profile: Int) {
            when (profile) {
                BluetoothProfile.A2DP -> a2dp = null
                BluetoothProfile.HEADSET -> headset = null
            }
        }
    }

    /** Fires onStateChanged(true, ...) if the selected headphones are already
     *  connected on this newly-bound proxy — closes the race between start()
     *  and asynchronous profile-proxy binding. Only fires when found in THIS
     *  proxy's list, so it fires at most once per bind (A2DP or HEADSET). */
    private fun reportIfAlreadyConnected(proxy: BluetoothProfile) {
        val address = selectedAddress ?: return
        if (!hasPermission()) return
        val device = try {
            proxy.connectedDevices.orEmpty().firstOrNull { it.address == address }
        } catch (e: SecurityException) {
            Log.w(TAG, "reportIfAlreadyConnected: $e")
            null
        } ?: return
        val name = try {
            device.name ?: address
        } catch (e: SecurityException) {
            address
        }
        onStateChanged?.invoke(true, address, name)
    }

    private val aclReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val device = IntentCompat.getParcelableExtra(
                intent, BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java
            ) ?: return
            if (!hasPermission()) return
            val address = device.address ?: return
            if (address != selectedAddress) return
            val name = try {
                device.name ?: address
            } catch (e: SecurityException) {
                address
            }
            when (intent.action) {
                BluetoothDevice.ACTION_ACL_CONNECTED -> {
                    if (guard.isActive) {
                        // The headphones auto-reconnected during the handoff
                        // window — release them again so the Mac can connect.
                        Log.d(TAG, "Guard active — re-releasing $address")
                        invokeProfile("disconnect", device)
                    } else {
                        onStateChanged?.invoke(true, address, name)
                    }
                }
                BluetoothDevice.ACTION_ACL_DISCONNECTED ->
                    onStateChanged?.invoke(false, address, name)
            }
        }
    }

    fun start() {
        if (!hasPermission()) {
            Log.w(TAG, "BLUETOOTH_CONNECT not granted — headphone handoff inactive")
            return
        }
        // Only bind proxies not already held — start() is called on every
        // reconnect and on every Settings refresh, and re-requesting an
        // already-bound proxy leaks a binding each time.
        if (a2dp == null) adapter?.getProfileProxy(context, profileListener, BluetoothProfile.A2DP)
        if (headset == null) adapter?.getProfileProxy(context, profileListener, BluetoothProfile.HEADSET)
        if (!receiverRegistered) {
            ContextCompat.registerReceiver(
                context,
                aclReceiver,
                IntentFilter().apply {
                    addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
                    addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
                },
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            receiverRegistered = true
        }
    }

    fun stop() {
        if (receiverRegistered) {
            context.unregisterReceiver(aclReceiver)
            receiverRegistered = false
        }
        a2dp?.let { adapter?.closeProfileProxy(BluetoothProfile.A2DP, it) }
        headset?.let { adapter?.closeProfileProxy(BluetoothProfile.HEADSET, it) }
        a2dp = null
        headset = null
    }

    /** Bonded devices in the audio major class (headphones, headsets, speakers). */
    fun bondedAudioDevices(): List<BondedDevice> {
        if (!hasPermission()) return emptyList()
        return try {
            adapter?.bondedDevices.orEmpty()
                .filter {
                    it.bluetoothClass?.majorDeviceClass ==
                        BluetoothClass.Device.Major.AUDIO_VIDEO
                }
                .map { BondedDevice(it.name ?: it.address, it.address) }
        } catch (e: SecurityException) {
            Log.w(TAG, "bondedAudioDevices: $e")
            emptyList()
        }
    }

    fun isConnected(address: String): Boolean {
        if (!hasPermission()) return false
        return try {
            a2dp?.connectedDevices.orEmpty().any { it.address == address } ||
                headset?.connectedDevices.orEmpty().any { it.address == address }
        } catch (e: SecurityException) {
            Log.w(TAG, "isConnected: $e")
            false
        }
    }

    /** Disconnect the headphones and hold off their auto-reconnect. */
    fun release(address: String): Boolean {
        if (!hasPermission()) return false
        val device = remoteDevice(address) ?: return false
        guard.arm(GUARD_MS)
        return invokeProfile("disconnect", device)
    }

    /** Connect the headphones to this phone. */
    fun takeover(address: String): Boolean {
        if (!hasPermission()) return false
        val device = remoteDevice(address) ?: return false
        guard.disarm()
        return invokeProfile("connect", device)
    }

    private fun remoteDevice(address: String): BluetoothDevice? = try {
        adapter?.getRemoteDevice(address)
    } catch (e: IllegalArgumentException) {
        Log.w(TAG, "Invalid Bluetooth address: $address")
        null
    }

    /** BluetoothA2dp/BluetoothHeadset connect()/disconnect() are hidden —
     *  invoke reflectively, treating any failure as "not done". */
    private fun invokeProfile(method: String, device: BluetoothDevice): Boolean {
        var ok = false
        for (proxy in listOfNotNull(a2dp, headset)) {
            try {
                val m = proxy.javaClass.getMethod(method, BluetoothDevice::class.java)
                if (m.invoke(proxy, device) == true) ok = true
            } catch (e: Exception) {
                Log.w(TAG, "$method via ${proxy.javaClass.simpleName} failed: $e")
            }
        }
        return ok
    }
}
