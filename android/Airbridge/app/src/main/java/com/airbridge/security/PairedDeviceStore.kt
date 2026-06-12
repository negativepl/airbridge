package com.airbridge.security

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONArray
import org.json.JSONObject

data class PairedDevice(
    val deviceName: String,
    val publicKeyBase64: String,
    val publicKeyFingerprint: String,
    val pairedAt: Long,
    /** SHA-256 hex of the Mac's TLS certificate DER, learned from the pairing QR.
     *  Empty = paired before TLS support → re-pairing required. */
    val certFingerprint: String = ""
)

internal fun PairedDevice.toJson(): JSONObject = JSONObject().apply {
    put("device_name", deviceName)
    put("public_key", publicKeyBase64)
    put("fingerprint", publicKeyFingerprint)
    put("paired_at", pairedAt)
    put("cert_fingerprint", certFingerprint)
}

internal fun pairedDeviceFromJson(obj: JSONObject): PairedDevice = PairedDevice(
    deviceName = obj.getString("device_name"),
    publicKeyBase64 = obj.getString("public_key"),
    publicKeyFingerprint = obj.getString("fingerprint"),
    pairedAt = obj.getLong("paired_at"),
    certFingerprint = obj.optString("cert_fingerprint", "")
)

class PairedDeviceStore(context: Context) {

    companion object {
        // Bumped on every mutation so Compose UI can re-read the store reactively
        // (the SharedPreferences-backed store is not otherwise observable).
        private val _revision = MutableStateFlow(0)
        val revision: StateFlow<Int> = _revision.asStateFlow()
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences("airbridge_paired_devices", Context.MODE_PRIVATE)

    fun getAll(): List<PairedDevice> {
        val json = prefs.getString("devices", "[]") ?: "[]"
        val arr = JSONArray(json)
        return (0 until arr.length()).map { i -> pairedDeviceFromJson(arr.getJSONObject(i)) }
    }

    fun add(device: PairedDevice) {
        val devices = getAll().toMutableList()
        devices.removeAll { it.publicKeyFingerprint == device.publicKeyFingerprint }
        devices.add(device)
        save(devices)
    }

    fun remove(fingerprint: String) {
        val devices = getAll().toMutableList()
        devices.removeAll { it.publicKeyFingerprint == fingerprint }
        save(devices)
    }

    fun isPaired(fingerprint: String): Boolean =
        getAll().any { it.publicKeyFingerprint == fingerprint }

    fun findByFingerprint(fingerprint: String): PairedDevice? =
        getAll().firstOrNull { it.publicKeyFingerprint == fingerprint }

    fun getAllFingerprints(): Set<String> =
        getAll().map { it.publicKeyFingerprint }.toSet()

    private fun save(devices: List<PairedDevice>) {
        val arr = JSONArray()
        devices.forEach { d -> arr.put(d.toJson()) }
        prefs.edit().putString("devices", arr.toString()).apply()
        _revision.update { it + 1 }
    }
}
