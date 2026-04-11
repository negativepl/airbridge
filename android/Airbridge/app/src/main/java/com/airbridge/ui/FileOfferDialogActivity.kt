package com.airbridge.ui

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.airbridge.R
import com.airbridge.service.AirbridgeService

/**
 * Transient activity that shows a dialog-style accept/reject prompt when the
 * user taps the incoming-file notification body. Replaces the previous
 * behavior of opening the main app on tap. Accept/reject buttons reuse the
 * same service actions as the notification's action buttons, so the notif
 * and the dialog stay in sync — picking either route triggers the same flow.
 *
 * The activity itself is translucent (see `Theme.Airbridge.TransparentDialog`
 * in `values/themes.xml`) and lives in its own task
 * (`taskAffinity=""` + `excludeFromRecents="true"` in the manifest) so
 * dismissing it returns the user to whatever they were doing instead of
 * dragging the main app into the foreground.
 */
class FileOfferDialogActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val transferId = intent.getStringExtra(EXTRA_TRANSFER_ID) ?: run {
            finish()
            return
        }
        val filename = intent.getStringExtra(EXTRA_FILENAME) ?: "file"
        val fileSize = intent.getLongExtra(EXTRA_FILE_SIZE, 0L)
        val sender = intent.getStringExtra(EXTRA_SENDER) ?: "Mac"

        val sizeText = when {
            fileSize > 1024 * 1024 -> String.format("%.1f MB", fileSize / (1024.0 * 1024.0))
            fileSize > 1024 -> String.format("%.0f KB", fileSize / 1024.0)
            else -> "$fileSize B"
        }

        // Pick up the user's theme preference so the dialog matches the app.
        val prefs = getSharedPreferences("airbridge_prefs", Context.MODE_PRIVATE)
        val themeMode = prefs.getString("theme_mode", "system") ?: "system"

        setContent {
            AirbridgeTheme(themeMode = themeMode) {
                AlertDialog(
                    onDismissRequest = {
                        // Tap-outside / back press: do NOT accept or reject.
                        // Just close the dialog — notification stays up so
                        // the user can tap Accept/Reject from the shade or
                        // tap the notif again to re-open this dialog.
                        finish()
                    },
                    icon = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Rounded.InsertDriveFile,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp)
                        )
                    },
                    title = {
                        // Material3's default AlertDialog title is headlineSmall
                        // (~24sp) which is too loud for a two-button prompt.
                        // Drop it to titleMedium (~16sp) so the dialog feels
                        // compact and matches notification-shade density.
                        Text(
                            text = stringResource(R.string.notification_accept_file, sender),
                            style = MaterialTheme.typography.titleMedium
                        )
                    },
                    text = {
                        Column {
                            Text(
                                text = filename,
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 3,
                                overflow = TextOverflow.Ellipsis
                            )
                            Spacer(Modifier.height(2.dp))
                            Text(
                                text = sizeText,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    },
                    confirmButton = {
                        TextButton(onClick = {
                            startService(
                                Intent(this, AirbridgeService::class.java).apply {
                                    action = AirbridgeService.ACTION_ACCEPT_FILE
                                    putExtra("transferId", transferId)
                                }
                            )
                            finish()
                        }) {
                            Text(stringResource(R.string.notification_accept))
                        }
                    },
                    dismissButton = {
                        TextButton(onClick = {
                            startService(
                                Intent(this, AirbridgeService::class.java).apply {
                                    action = AirbridgeService.ACTION_REJECT_FILE
                                    putExtra("transferId", transferId)
                                }
                            )
                            finish()
                        }) {
                            Text(stringResource(R.string.notification_reject))
                        }
                    }
                )
            }
        }
    }

    companion object {
        const val EXTRA_TRANSFER_ID = "transferId"
        const val EXTRA_FILENAME = "filename"
        const val EXTRA_FILE_SIZE = "fileSize"
        const val EXTRA_SENDER = "sender"
    }
}
