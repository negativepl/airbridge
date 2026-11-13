package com.airbridge.share

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.airbridge.R
import com.airbridge.security.PairedDeviceStore

/**
 * Direct Share: every paired Mac is a sharing shortcut, so it appears in the
 * top row of Android's share sheet and a share goes straight to it (see
 * ShareReceiverActivity). The shortcuts are kept off the launcher, whose
 * long-press menu holds the static ones from res/xml/shortcuts.xml.
 */
object MacShareShortcuts {
    private const val TAG = "MacShareShortcuts"
    private const val CATEGORY = "com.airbridge.category.SEND_TO_MAC"
    private const val ID_PREFIX = "mac-"

    /** The paired Mac a Direct Share shortcut stands for, by its key fingerprint. */
    fun fingerprintOf(shortcutId: String?): String? =
        shortcutId?.takeIf { it.startsWith(ID_PREFIX) }?.removePrefix(ID_PREFIX)

    fun shortcutIdFor(fingerprint: String) = ID_PREFIX + fingerprint

    /**
     * Publishes one shortcut per paired Mac, replacing the previous set. Runs
     * when the service starts and when a Mac is paired or unpaired. There is
     * no "already published" check: shortcuts kept off the launcher are not
     * returned by getDynamicShortcuts, so the published set cannot be read back.
     */
    fun update(context: Context) {
        val macs = PairedDeviceStore(context).getAll()
        val shortcuts = macs.map { mac ->
            ShortcutInfoCompat.Builder(context, shortcutIdFor(mac.publicKeyFingerprint))
                .setShortLabel(mac.deviceName)
                .setLongLabel(context.getString(R.string.share_shortcut_long, mac.deviceName))
                .setIcon(IconCompat.createWithResource(context, R.drawable.ic_shortcut_mac))
                // Required, but a share through the shortcut goes to the share target.
                .setIntent(Intent(context, ShareReceiverActivity::class.java).setAction(Intent.ACTION_SEND))
                .setCategories(setOf(CATEGORY))
                .setLongLived(true)
                .setExcludedFromSurfaces(ShortcutInfoCompat.SURFACE_LAUNCHER)
                .build()
        }
        val ok = runCatching { ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts) }
            .onFailure { Log.w(TAG, "Share shortcuts not published", it) }
            .getOrDefault(false)
        if (ok) Log.i(TAG, "Share shortcuts published for ${shortcuts.size} Mac(s)")
        else Log.w(TAG, "Share shortcuts not published (rate limited)")
    }

    /** Ranks the Mac higher in the share sheet after a share to it. */
    fun reportUsed(context: Context, fingerprint: String) =
        ShortcutManagerCompat.reportShortcutUsed(context, shortcutIdFor(fingerprint))
}
