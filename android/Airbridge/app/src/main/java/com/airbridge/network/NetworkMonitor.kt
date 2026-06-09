package com.airbridge.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.util.Log

/**
 * Watches the device's default network and reports when it switches to a
 * different network (e.g. moving from work Wi-Fi to home Wi-Fi). The first
 * network seen after [start] is treated as the baseline and does NOT trigger a
 * change callback — only a switch to a genuinely different [Network] does.
 */
class NetworkMonitor(
    context: Context,
    private val onNetworkChanged: () -> Unit,
) {
    companion object {
        private const val TAG = "NetworkMonitor"
    }

    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private var currentNetwork: Network? = null
    private var hasBaseline = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val previous = currentNetwork
            currentNetwork = network
            // The first network seen is the baseline (discovery is already
            // running at startup). Any later switch to a different network —
            // including one that arrives after a brief drop — triggers a refresh.
            if (!hasBaseline) {
                hasBaseline = true
                return
            }
            if (previous != network) {
                Log.d(TAG, "Default network changed ($previous -> $network)")
                onNetworkChanged()
            }
        }

        override fun onLost(network: Network) {
            if (network == currentNetwork) {
                currentNetwork = null
            }
        }
    }

    fun start() {
        try {
            connectivityManager.registerDefaultNetworkCallback(callback)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register network callback", e)
        }
    }

    fun stop() {
        try {
            connectivityManager.unregisterNetworkCallback(callback)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to unregister network callback", e)
        }
        currentNetwork = null
        hasBaseline = false
    }
}
