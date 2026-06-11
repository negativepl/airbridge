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

    // Lifecycle state. All transitions happen under the NsdDiscovery lock —
    // NsdManager delivers listener callbacks on its own internal thread, while
    // start/stop/restart may arrive from the main thread or a socket thread.
    private var isDiscovering = false   // between onDiscoveryStarted and stop completion
    private var isStopping = false      // stopServiceDiscovery() sent, waiting for its callback
    private var pendingStart = false    // start requested while a stop is still in flight

    // NsdManager requires a distinct DiscoveryListener instance per
    // discoverServices() call — a stopped listener cannot be reused. We create
    // a fresh one on each startDiscovery() so discovery can be restarted (e.g.
    // after a Wi-Fi change) to find the peer on the new network. The listener
    // stays "active" until its stop actually completes, so late callbacks from
    // an already-replaced listener can be recognized and ignored.
    private var activeListener: NsdManager.DiscoveryListener? = null

    private val nsdManager: NsdManager by lazy {
        context.getSystemService(Context.NSD_SERVICE) as NsdManager
    }

    private fun createDiscoveryListener() = object : NsdManager.DiscoveryListener {
        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e(TAG, "Discovery start failed: error $errorCode")
            synchronized(this@NsdDiscovery) {
                // NsdManager delivers nothing further for this listener.
                if (this === activeListener) {
                    activeListener = null
                    isDiscovering = false
                    isStopping = false
                }
            }
        }

        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
            Log.e(TAG, "Discovery stop failed: error $errorCode")
            finishStop(this)
        }

        override fun onDiscoveryStarted(serviceType: String) {
            synchronized(this@NsdDiscovery) {
                if (this !== activeListener) return
                isDiscovering = true
            }
            Log.d(TAG, "Discovery started for $serviceType")
        }

        override fun onDiscoveryStopped(serviceType: String) {
            Log.d(TAG, "Discovery stopped for $serviceType")
            finishStop(this)
        }

        override fun onServiceFound(serviceInfo: NsdServiceInfo) {
            synchronized(this@NsdDiscovery) {
                // A replaced (or stopping) listener can still deliver finds for
                // a moment — acting on them would double-connect to the Mac.
                if (this !== activeListener || isStopping) {
                    Log.d(TAG, "Ignoring onServiceFound from stale listener: ${serviceInfo.serviceName}")
                    return
                }
            }
            Log.d(TAG, "Service found: ${serviceInfo.serviceName}")
            nsdManager.resolveService(serviceInfo, createResolveListener(this))
        }

        override fun onServiceLost(serviceInfo: NsdServiceInfo) {
            synchronized(this@NsdDiscovery) {
                if (this !== activeListener) return
            }
            Log.d(TAG, "Service lost: ${serviceInfo.serviceName}")
            onServiceLost?.invoke()
        }
    }

    private fun createResolveListener(owner: NsdManager.DiscoveryListener) = object : NsdManager.ResolveListener {
        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
            Log.e(TAG, "Resolve failed for ${serviceInfo.serviceName}: error $errorCode")
        }

        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
            synchronized(this@NsdDiscovery) {
                // A resolve can complete after the discovery that requested it
                // was stopped/replaced (network change) — drop it; the fresh
                // discovery will resolve the peer on the current network.
                if (owner !== activeListener) {
                    Log.d(TAG, "Ignoring resolve result from stale discovery: ${serviceInfo.serviceName}")
                    return
                }
            }
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

    // Calling into NsdManager while holding the NsdDiscovery lock — on the
    // thread of its own callbacks, no less — is a fragile, potentially
    // deadlock-prone window. Lock-held helpers therefore only mutate state and
    // return which NsdManager call to make; the call itself runs after the
    // lock is released. The listener instance is created under the lock and
    // passed out, so the unlocked call targets exactly the instance the lock
    // approved even if state changes in between.
    private sealed interface NsdCall {
        class Start(val listener: NsdManager.DiscoveryListener) : NsdCall
        class Stop(val listener: NsdManager.DiscoveryListener) : NsdCall
        object None : NsdCall
    }

    /** Performs the NsdManager call decided under the lock. Must be called WITHOUT the lock held. */
    private fun perform(call: NsdCall) {
        when (call) {
            is NsdCall.Start ->
                nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, call.listener)
            is NsdCall.Stop ->
                try {
                    nsdManager.stopServiceDiscovery(call.listener)
                } catch (e: Exception) {
                    Log.e(TAG, "Error stopping discovery", e)
                    // The stop request never reached NsdManager — complete the
                    // cycle here so a pending restart isn't stuck forever.
                    finishStop(call.listener)
                }
            NsdCall.None -> Unit
        }
    }

    fun startDiscovery() {
        perform(synchronized(this) { startLocked() })
    }

    fun stopDiscovery() {
        perform(
            synchronized(this) {
                pendingStart = false
                stopLocked()
            }
        )
    }

    /**
     * Restart discovery with a fresh listener — used after a network change.
     * The new discovery starts only after NsdManager confirms the old one has
     * stopped (onDiscoveryStopped / onStopDiscoveryFailed); starting earlier
     * would let the old listener race the new one with duplicate finds.
     */
    fun restart() {
        perform(
            synchronized(this) {
                pendingStart = true
                stopLocked()
            }
        )
    }

    /** Must be called with the NsdDiscovery lock held. */
    private fun startLocked(): NsdCall {
        if (isStopping) {
            // The previous discovery is still shutting down — starting now
            // would run two discoveries in parallel and the old listener could
            // keep delivering onServiceFound. Defer until the stop completes.
            Log.d(TAG, "Stop still in flight — deferring discovery start")
            pendingStart = true
            return NsdCall.None
        }
        if (activeListener != null) {
            Log.d(TAG, "Discovery already running — skipping")
            return NsdCall.None
        }
        val listener = createDiscoveryListener()
        activeListener = listener
        return NsdCall.Start(listener)
    }

    /** Must be called with the NsdDiscovery lock held. */
    private fun stopLocked(): NsdCall {
        val listener = activeListener
        if (listener == null) {
            // Nothing to stop — if a (re)start was requested, run it now.
            if (pendingStart) {
                pendingStart = false
                return startLocked()
            }
            return NsdCall.None
        }
        if (isStopping) return NsdCall.None // stop already in flight; pendingStart applies when it completes
        isStopping = true
        return NsdCall.Stop(listener)
    }

    /** Completes a stop cycle for [listener]; calls from stale listeners are no-ops. */
    private fun finishStop(listener: NsdManager.DiscoveryListener) {
        perform(synchronized(this) { finishStopLocked(listener) })
    }

    /** Must be called with the NsdDiscovery lock held. */
    private fun finishStopLocked(listener: NsdManager.DiscoveryListener): NsdCall {
        if (listener !== activeListener) return NsdCall.None
        activeListener = null
        isDiscovering = false
        isStopping = false
        if (pendingStart) {
            pendingStart = false
            return startLocked()
        }
        return NsdCall.None
    }
}
