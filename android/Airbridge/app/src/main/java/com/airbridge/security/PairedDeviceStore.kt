package com.airbridge.security

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

data class PairedDevice(
    val deviceName: String,
    val publicKeyBase64: String,
    val publicKeyFingerprint: String,
    val pairedAt: Long
)

class PairedDeviceStore(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("airbridge_paired_devices", Context.MODE_PRIVATE)

    fun getAll(): List<PairedDevice> {
        val json = prefs.getString("devices", "[]") ?: "[]"
        val arr = JSONArray(json)
        return (0 until arr.length()).map { i ->
            val obj = arr.getJSONObject(i)
            PairedDevice(
                deviceName = obj.getString("device_name"),
                publicKeyBase64 = obj.getString("public_key"),
                publicKeyFingerprint = obj.getString("fingerprint"),
                pairedAt = obj.getLong("paired_at")
            )
        }
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
        devices.forEach { d ->
            arr.put(JSONObject().apply {
                put("device_name", d.deviceName)
                put("public_key", d.publicKeyBase64)
                put("fingerprint", d.publicKeyFingerprint)
                put("paired_at", d.pairedAt)
            })
        }
        prefs.edit().putString("devices", arr.toString()).apply()
    }
}
