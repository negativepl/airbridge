package com.airbridge.notification

import android.app.Notification

/**
 * Czy dane powiadomienie warto przekazać na Maca. Odsiewa szum: trwałe (ongoing),
 * grupowe podsumowania, własne powiadomienia Airbridge i puste (brak tytułu i treści).
 */
fun shouldRelayNotification(
    flags: Int,
    packageName: String,
    ownPackage: String,
    title: String?,
    text: String?
): Boolean {
    if (flags and Notification.FLAG_ONGOING_EVENT != 0) return false
    if (flags and Notification.FLAG_GROUP_SUMMARY != 0) return false
    if (packageName == ownPackage) return false
    if (title.isNullOrBlank() && text.isNullOrBlank()) return false
    return true
}
