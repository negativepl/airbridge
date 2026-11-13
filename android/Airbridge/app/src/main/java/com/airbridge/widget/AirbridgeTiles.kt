package com.airbridge.widget

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import com.airbridge.R
import com.airbridge.service.AirbridgeService
import com.airbridge.ui.currentMirrorIntent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Quick Settings tiles for the quick actions. A tap collapses the panel and
 * runs the action in WidgetActionActivity, as the widgets and app shortcuts
 * do (which is also what lets the clipboard be read). The tile shows the
 * connected Mac's name, and is unavailable while no Mac is connected.
 *
 * Enabled from Android 14 (res/values-v34/bools.xml): that is where a tile
 * opens an activity through a PendingIntent; the Intent variant before it is
 * deprecated.
 */
abstract class QuickActionTileService(private val action: String) : TileService() {

    private var scope: CoroutineScope? = null

    override fun onStartListening() {
        super.onStartListening()
        // Follow the connection while the panel is open.
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main).also { scope ->
            scope.launch {
                combine(AirbridgeService.isConnected, AirbridgeService.connectedDeviceName) { connected, name ->
                    connected to name
                }.collect { (connected, name) -> render(connected, name) }
            }
        }
    }

    override fun onStopListening() {
        scope?.cancel()
        scope = null
        super.onStopListening()
    }

    private fun render(connected: Boolean, macName: String?) {
        val tile = qsTile ?: return
        val available = connected && (action != WidgetActionActivity.ACTION_MAC_SCREEN || currentMirrorIntent(this, 0) != null)
        tile.state = if (available) Tile.STATE_INACTIVE else Tile.STATE_UNAVAILABLE
        tile.subtitle = if (available) macName else getString(R.string.not_connected)
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        // The tiles are only enabled from Android 14, so the check always holds.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val intent = WidgetActionActivity.intent(this, action)
            startActivityAndCollapse(
                PendingIntent.getActivity(this, action.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE)
            )
        }
    }

    companion object {
        /** The tiles, for offering them in the app's settings (StatusBarManager.requestAddTileService). */
        val all: List<QuickActionTile> = listOf(
            QuickActionTile(ClipboardTileService::class.java, R.string.action_send_clipboard, R.drawable.ic_widget_clipboard),
            QuickActionTile(FileTileService::class.java, R.string.action_send_file, R.drawable.ic_widget_file),
            QuickActionTile(PhotoTileService::class.java, R.string.action_send_photo, R.drawable.ic_widget_photo),
            QuickActionTile(ScanTileService::class.java, R.string.quick_scan, R.drawable.ic_widget_scan),
            QuickActionTile(MacScreenTileService::class.java, R.string.quick_mac_screen, R.drawable.ic_widget_mac_screen),
        )
    }
}

/** One tile as the app's settings offer it. */
data class QuickActionTile(
    val service: Class<out TileService>,
    @StringRes val label: Int,
    @DrawableRes val icon: Int,
) {
    fun component(context: Context) = ComponentName(context, service)
    fun icon(context: Context): Icon = Icon.createWithResource(context, icon)
}

class ClipboardTileService : QuickActionTileService(WidgetActionActivity.ACTION_CLIPBOARD)

class FileTileService : QuickActionTileService(WidgetActionActivity.ACTION_FILE)

class PhotoTileService : QuickActionTileService(WidgetActionActivity.ACTION_PHOTO)

class ScanTileService : QuickActionTileService(WidgetActionActivity.ACTION_SCAN)

class MacScreenTileService : QuickActionTileService(WidgetActionActivity.ACTION_MAC_SCREEN)
