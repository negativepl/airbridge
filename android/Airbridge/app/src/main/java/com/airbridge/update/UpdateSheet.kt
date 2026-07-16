package com.airbridge.update

import android.util.Log
import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.ui.Alignment
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.airbridge.R
import kotlinx.coroutines.launch
import java.io.File
import java.util.Locale

/**
 * Self-contained manual update-check flow. Settings and About both just flip
 * [trigger] to true from their row's onClick; this hosts every state — the
 * "checking" beat, the up-to-date/failure toasts, and the changelog sheet
 * with download progress and install button.
 *
 * Never runs on its own — only when the user explicitly asks (transparency
 * rule from [UpdateChecker]'s doc comment).
 */
private sealed class FlowState {
    object Idle : FlowState()
    object Checking : FlowState()
    data class Available(val manifest: UpdateManifest) : FlowState()
    data class UpToDate(val installedVersion: String) : FlowState()
}

private sealed class DownloadState {
    object NotStarted : DownloadState()
    data class InProgress(val progress: Float) : DownloadState()
    data class Done(val apk: File) : DownloadState()
    object VerifyFailed : DownloadState()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpdateFlowHost(trigger: Boolean, onDone: () -> Unit) {
    val context = LocalContext.current
    val failedMsg = stringResource(R.string.update_failed)

    var state by remember { mutableStateOf<FlowState>(FlowState.Idle) }

    LaunchedEffect(trigger) {
        if (!trigger) return@LaunchedEffect
        state = FlowState.Checking
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val installedVersionCode = packageInfo.longVersionCode.toInt()
        when (val result = UpdateChecker().check(installedVersionCode)) {
            is UpdateChecker.CheckResult.UpdateAvailable -> {
                state = FlowState.Available(result.manifest)
            }
            UpdateChecker.CheckResult.UpToDate -> {
                state = FlowState.UpToDate(packageInfo.versionName ?: "")
            }
            is UpdateChecker.CheckResult.Failed -> {
                Log.w("UpdateFlow", result.reason)
                Toast.makeText(context, failedMsg, Toast.LENGTH_SHORT).show()
                state = FlowState.Idle
                onDone()
            }
        }
    }

    // The sheet appears as soon as the check starts (Checking), then morphs
    // its content into the changelog (Available) or the up-to-date
    // confirmation (UpToDate). Only Failed resolves straight back to Idle
    // above, after its toast, so the sheet isn't shown for it.
    val currentState = state
    if (currentState !is FlowState.Idle) {
        @Suppress("DEPRECATION")
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = {
                state = FlowState.Idle
                onDone()
            },
            sheetState = sheetState
        ) {
            when (currentState) {
                is FlowState.Checking -> UpdateCheckingSheet()
                is FlowState.Available -> UpdateAvailableSheet(
                    manifest = currentState.manifest,
                    onInstalled = {
                        state = FlowState.Idle
                        onDone()
                    }
                )
                is FlowState.UpToDate -> UpdateUpToDateSheet(
                    installedVersion = currentState.installedVersion
                )
                FlowState.Idle -> {}
            }
        }
    }
}

@Composable
private fun UpdateCheckingSheet() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        CircularProgressIndicator()
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = stringResource(R.string.update_checking),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun UpdateUpToDateSheet(installedVersion: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Rounded.CheckCircle,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(48.dp)
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = stringResource(R.string.update_up_to_date),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface
        )
        if (installedVersion.isNotEmpty()) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = stringResource(R.string.update_installed_version, installedVersion),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun UpdateAvailableSheet(
    manifest: UpdateManifest,
    onInstalled: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var downloadState by remember { mutableStateOf<DownloadState>(DownloadState.NotStarted) }

    val changelog = remember(manifest) {
        if (Locale.getDefault().language == "pl") manifest.changelogPl else manifest.changelogEn
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 8.dp)
    ) {
        Text(
            text = stringResource(R.string.update_available_title, manifest.version),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface
        )

        Spacer(modifier = Modifier.height(4.dp))

        Text(
            text = stringResource(R.string.update_published, manifest.publishedAt),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(20.dp))

        Text(
            text = stringResource(R.string.update_whats_new),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface
        )

        Spacer(modifier = Modifier.height(8.dp))

        Column {
            changelog.forEach { entry ->
                Row(modifier = Modifier.padding(bottom = 6.dp)) {
                    Text(
                        text = "•  ",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = entry,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        when (val ds = downloadState) {
            is DownloadState.InProgress -> {
                LinearProgressIndicator(
                    progress = { ds.progress },
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = stringResource(R.string.update_downloading, (ds.progress * 100).toInt()),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(16.dp))
            }
            DownloadState.VerifyFailed -> {
                Text(
                    text = stringResource(R.string.update_verify_failed),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error
                )
                Spacer(modifier = Modifier.height(16.dp))
            }
            else -> {}
        }

        val ds = downloadState
        if (ds is DownloadState.Done) {
            Button(
                onClick = {
                    ApkInstaller(context).launchInstall(ds.apk)
                    onInstalled()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
            ) {
                Text(stringResource(R.string.update_download_install))
            }
        } else {
            Button(
                onClick = {
                    downloadState = DownloadState.InProgress(0f)
                    scope.launch {
                        val installer = ApkInstaller(context)
                        val apk = installer.downloadAndVerify(manifest.android) { progress ->
                            downloadState = DownloadState.InProgress(progress)
                        }
                        downloadState = if (apk != null) DownloadState.Done(apk) else DownloadState.VerifyFailed
                    }
                },
                enabled = downloadState !is DownloadState.InProgress,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
            ) {
                Text(stringResource(R.string.update_download_install))
            }
        }

        Spacer(modifier = Modifier.height(32.dp))
    }
}
