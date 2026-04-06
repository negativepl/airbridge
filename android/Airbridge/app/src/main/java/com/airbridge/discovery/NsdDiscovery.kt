package com.airbridge.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

class NsdDiscovery(private val context: Context) {

    companion object {
        private const val TAG = "NsdDiscovery"
        private const val SERVICE_TYPE = "_airbridge._tcp."
    }

    var onServiceFound: ((host: String, port: Int, deviceName: String, httpPort: Int, fingerprint: String) -> Unit)? = null
    var onServiceLost: (() -> Unit)? = null

    @Volatile
    private var isDiscovering = false

    private val nsdManager: NsdManager by lazy {
        context.getSystemService(Context.NSD_SERVICE) as NsdManager
    }

    private val discoveryListener = object : NsdManager.DiscoveryListener {
        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e(TAG, "Discovery start failed: error $errorCode")
        }

        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e(TAG, "Discovery stop failed: error $errorCode")
        }

        override fun onDiscoveryStarted(serviceType: String) {
            isDiscovering = true
            Log.d(TAG, "Discovery started for $serviceType")
        }

        override fun onDiscoveryStopped(serviceType: String) {
            isDiscovering = false
            Log.d(TAG, "Discovery stopped for $serviceType")
        }

        override fun onServiceFound(serviceInfo: NsdServiceInfo) {
            Log.d(TAG, "Service found: ${serviceInfo.serviceName}")
            nsdManager.resolveService(serviceInfo, createResolveListener())
        }

        override fun onServiceLost(serviceInfo: NsdServiceInfo) {
            Log.d(TAG, "Service lost: ${serviceInfo.serviceName}")
            onServiceLost?.invoke()
        }
    }

    private fun createResolveListener() = object : NsdManager.ResolveListener {
        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
            Log.e(TAG, "Resolve failed for ${serviceInfo.serviceName}: error $errorCode")
        }

        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
            val host = serviceInfo.host?.hostAddress ?: return
            val port = serviceInfo.port
            val name = serviceInfo.serviceName ?: "Mac"
            val httpPortStr = serviceInfo.attributes["http_port"]?.let { String(it, Charsets.UTF_8) }
            val httpPort = httpPortStr?.toIntOrNull() ?: 8766
            val fingerprint = serviceInfo.attributes["pk_fingerprint"]?.let { String(it, Charsets.UTF_8) } ?: ""
            Log.d(TAG, "Service resolved: $name at $host:$port (httpPort=$httpPort, fp=${fingerprint.take(16)}...)")
            onServiceFound?.invoke(host, port, name, httpPort, fingerprint)
        }
    }

    fun startDiscovery() {
        if (isDiscovering) {
            Log.d(TAG, "Discovery already running — skipping")
            return
        }
        nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
    }

    fun stopDiscovery() {
        if (!isDiscovering) return
        try {
            nsdManager.stopServiceDiscovery(discoveryListener)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping discovery", e)
        }
        isDiscovering = false
    }
}
