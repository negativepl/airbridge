package com.airbridge.notification

import android.app.Notification
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationFilterTest {
    private val own = "com.airbridge"

    @Test fun relaysNormalNotification() {
        assertTrue(shouldRelayNotification(flags = 0, packageName = "com.whatsapp", ownPackage = own, title = "A", text = "B"))
    }

    @Test fun skipsOngoing() {
        assertFalse(shouldRelayNotification(flags = Notification.FLAG_ONGOING_EVENT, packageName = "x", ownPackage = own, title = "A", text = "B"))
    }

    @Test fun skipsGroupSummary() {
        assertFalse(shouldRelayNotification(flags = Notification.FLAG_GROUP_SUMMARY, packageName = "x", ownPackage = own, title = "A", text = "B"))
    }

    @Test fun skipsOwnApp() {
        assertFalse(shouldRelayNotification(flags = 0, packageName = own, ownPackage = own, title = "A", text = "B"))
    }

    @Test fun skipsEmpty() {
        assertFalse(shouldRelayNotification(flags = 0, packageName = "x", ownPackage = own, title = null, text = "  "))
    }

    @Test fun relaysTitleOnly() {
        assertTrue(shouldRelayNotification(flags = 0, packageName = "x", ownPackage = own, title = "A", text = null))
    }
}
