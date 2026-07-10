package com.airbridge.service

import android.Manifest
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothLeAudio
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
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

    /** De-bounce: several profiles (A2DP/HEADSET/LE_AUDIO) fire per physical
     *  connect/disconnect. Only forward onStateChanged on an actual transition. */
    private var lastReportedConnected: Boolean? = null

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED

    /** LE Audio dual mode keeps profile links alive on both hosts; the honest
     *  "headphones are here" signal is whether the system audio routing exposes
     *  them as an output device (symmetric to CoreAudio presence on the Mac). */
    private fun isAudioRoutedHere(address: String): Boolean {
        if (!hasPermission()) return false
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        val isLeAudioType: (AudioDeviceInfo) -> Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            { it.type == AudioDeviceInfo.TYPE_BLE_HEADSET || it.type == AudioDeviceInfo.TYPE_BLE_SPEAKER }
        } else {
            { false }
        }
        return try {
            am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
                (it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || isLeAudioType(it)) &&
                    it.address.equals(address, ignoreCase = true)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "isAudioRoutedHere: $e")
            false
        }
    }

    /** Reacts to any change in the system's audio output device set. This is
     *  the primary state source (see [isAudioRoutedHere]) — profile broadcasts
     *  and proxy-bind catch-up below are kept only as redundant backup triggers,
     *  since they still fire correctly for classic (non-LE-Audio) headsets and
     *  are cheap and harmless to leave in place. */
    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            handleAudioRouteChange()
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            handleAudioRouteChange()
        }
    }

    private fun handleAudioRouteChange() {
        val address = selectedAddress ?: return
        if (!hasPermission()) return
        val device = remoteDevice(address) ?: return
        val name = try {
            device.name ?: address
        } catch (e: SecurityException) {
            address
        }
        reportStateChange(isAudioRoutedHere(address), address, name, device)
    }

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
        // Proxy-bind catch-up is a backup trigger — recompute the real state
        // via isAudioRoutedHere rather than assuming "profile connected" means
        // "audio here" (false on LE Audio dual mode, see class doc above).
        reportStateChange(isAudioRoutedHere(address), address, name, device)
    }

    /** Forward a connected/disconnected transition, de-bounced against
     *  repeated events from multiple profiles/sources reporting the same
     *  effective state (see [lastReportedConnected]). */
    private fun reportStateChange(connected: Boolean, address: String, name: String, device: BluetoothDevice) {
        if (connected && guard.isActive) {
            // The headphones auto-reconnected during the handoff window —
            // release them again so the Mac can connect.
            Log.d(TAG, "Guard active — re-releasing $address")
            invokeProfile("disconnect", device)
            return
        }
        if (lastReportedConnected == connected) return
        lastReportedConnected = connected
        onStateChanged?.invoke(connected, address, name)
    }

    // Samsung's Galaxy Buds (LE Audio dual mode) keep the classic ACL link up
    // across a "reconnect" — only the audio profile activates. That means
    // BluetoothDevice.ACTION_ACL_CONNECTED never fires on reconnect, and we'd
    // miss the event entirely. Profile-level connection-state broadcasts
    // (A2DP/HEADSET/LE_AUDIO) fire in both cases and are the reliable source
    // of truth; ACL_DISCONNECTED is kept as a belt-and-suspenders signal for
    // a full link drop (e.g. out of range, powered off).
    private val stateReceiver = object : BroadcastReceiver() {
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
            val isProfileStateAction = intent.action == BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED ||
                intent.action == BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    intent.action == BluetoothLeAudio.ACTION_LE_AUDIO_CONNECTION_STATE_CHANGED)
            // Profile broadcasts are now a backup trigger — the AudioDeviceCallback
            // registered in start() is the primary source. Recompute the real
            // state via isConnected() (== isAudioRoutedHere) rather than assuming
            // "profile connected" means "audio here" (false on LE Audio dual mode).
            val state = intent.getIntExtra(BluetoothProfile.EXTRA_STATE, -1)
            val isSettledProfileState = isProfileStateAction &&
                (state == BluetoothProfile.STATE_CONNECTED || state == BluetoothProfile.STATE_DISCONNECTED)
            // CONNECTING/DISCONNECTING are intermediate — ignore.
            if (isSettledProfileState || intent.action == BluetoothDevice.ACTION_ACL_DISCONNECTED) {
                reportStateChange(isConnected(address), address, name, device)
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
                stateReceiver,
                IntentFilter().apply {
                    addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
                    addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        addAction(BluetoothLeAudio.ACTION_LE_AUDIO_CONNECTION_STATE_CHANGED)
                    }
                    // Belt-and-suspenders: a full link drop (out of range, powered
                    // off) always fires ACL_DISCONNECTED even when no profile
                    // broadcast does.
                    addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
                },
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
            receiverRegistered = true
        }
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        am?.registerAudioDeviceCallback(audioDeviceCallback, null)
    }

    fun stop() {
        if (receiverRegistered) {
            context.unregisterReceiver(stateReceiver)
            receiverRegistered = false
        }
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        am?.unregisterAudioDeviceCallback(audioDeviceCallback)
        a2dp?.let { adapter?.closeProfileProxy(BluetoothProfile.A2DP, it) }
        headset?.let { adapter?.closeProfileProxy(BluetoothProfile.HEADSET, it) }
        a2dp = null
        headset = null
        lastReportedConnected = null
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

    /** Whether audio is currently routed to these headphones on this phone.
     *  This is NOT profile connection state — on LE Audio dual-mode gear the
     *  classic/profile link can stay up on both hosts while audio actually
     *  plays elsewhere, so the audio route (see [isAudioRoutedHere]) is the
     *  only honest signal. */
    fun isConnected(address: String): Boolean = isAudioRoutedHere(address)

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
