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

    var onServiceFound: ((host: String, port: Int, deviceName: String, httpPort: Int, fingerprint: String, mirrorPort: Int?) -> Unit)? = null
    var onServiceLost: (() -> Unit)? = null

    @Volatile
    private var isDiscovering = false

    // NsdManager requires a distinct DiscoveryListener instance per
    // discoverServices() call — a stopped listener cannot be reused. We create
    // a fresh one on each startDiscovery() so discovery can be restarted (e.g.
    // after a Wi-Fi change) to find the peer on the new network.
    private var activeListener: NsdManager.DiscoveryListener? = null

    private val nsdManager: NsdManager by lazy {
        context.getSystemService(Context.NSD_SERVICE) as NsdManager
    }

    private fun createDiscoveryListener() = object : NsdManager.DiscoveryListener {
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
            val mirrorPortStr = serviceInfo.attributes["mirror_port"]?.let { String(it, Charsets.UTF_8) }
            val mirrorPort = mirrorPortStr?.toIntOrNull()
            val fingerprint = serviceInfo.attributes["pk_fingerprint"]?.let { String(it, Charsets.UTF_8) } ?: ""
            Log.d(TAG, "Service resolved: $name at $host:$port (httpPort=$httpPort, mirrorPort=$mirrorPort, fp=${fingerprint.take(16)}...)")
            onServiceFound?.invoke(host, port, name, httpPort, fingerprint, mirrorPort)
        }
    }

    fun startDiscovery() {
        if (isDiscovering) {
            Log.d(TAG, "Discovery already running — skipping")
            return
        }
        val listener = createDiscoveryListener()
        activeListener = listener
        nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun stopDiscovery() {
        val listener = activeListener ?: return
        if (!isDiscovering) return
        try {
            nsdManager.stopServiceDiscovery(listener)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping discovery", e)
        }
        activeListener = null
        isDiscovering = false
    }

    /** Restart discovery with a fresh listener — used after a network change. */
    fun restart() {
        stopDiscovery()
        startDiscovery()
    }
}
