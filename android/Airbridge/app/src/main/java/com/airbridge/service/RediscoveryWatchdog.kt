package com.airbridge.service

/**
 * Level-triggered safety net for NSD discovery.
 *
 * The phone normally (re)starts discovery on the *edge* of a network change
 * (NetworkMonitor -> onNetworkChanged -> NsdDiscovery.restart). If that single
 * attempt is missed or fails — Wi-Fi joined while the phone is in Doze with
 * multicast throttled, or the Mac re-advertised a moment after discovery
 * already ran — nothing recovers it: the phone sits on the right network,
 * disconnected, indefinitely, because no *new* network event will arrive.
 *
 * This watchdog is the level-triggered backstop. It is ticked on a fixed
 * cadence while the service runs and asks the caller to force a fresh
 * discovery whenever the connection has been down for [intervalTicks]
 * consecutive ticks. Pure logic, no Android dependencies, so it can be unit
 * tested deterministically — the caller owns the clock and the NsdManager call.
 */
class RediscoveryWatchdog(private val intervalTicks: Int = 2) {

    private var ticksDown = 0

    /**
     * Advance the watchdog by one tick.
     *
     * @param isConnected whether the WebSocket is currently authenticated.
     * @return true when the caller should force a re-discovery now.
     */
    fun onTick(isConnected: Boolean): Boolean {
        if (isConnected) {
            ticksDown = 0
            return false
        }
        ticksDown++
        if (ticksDown >= intervalTicks) {
            ticksDown = 0
            return true
        }
        return false
    }
}
