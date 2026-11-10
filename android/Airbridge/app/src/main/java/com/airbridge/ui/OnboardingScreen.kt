package com.airbridge.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerDefaults
import androidx.compose.foundation.pager.rememberPagerState
import androidx.graphics.shapes.RoundedPolygon
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.ui.graphics.graphicsLayer
import kotlin.math.absoluteValue
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.ScreenShare
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Call
import androidx.compose.material.icons.rounded.ChatBubble
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Contacts
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Photo
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material.icons.rounded.Wifi
import androidx.compose.foundation.Image
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import com.airbridge.R
import kotlinx.coroutines.launch

// "All files access" (MANAGE_EXTERNAL_STORAGE) only exists from API 30 (R). On API 29
// the method is absent — calling it would crash — and the grant is unobtainable, so the
// files feature is simply reported as ungranted there.
private fun isAllFilesAccessGranted(): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun OnboardingScreen(
    onFinished: () -> Unit,
    onScanQr: () -> Unit,
    onSkipPairing: () -> Unit = onFinished
) {
    val pagerState = rememberPagerState(pageCount = { 4 })
    val coroutineScope = rememberCoroutineScope()
    // The spring the app's own screen transitions run on (AppNavHost).
    val stepSpatial = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()

    Scaffold(
        containerColor = MaterialTheme.colorScheme.pageBackground,
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f),
                // Every step is composed up front. Composed as it slid in, a
                // step cost one long frame at the start of its first transition.
                beyondViewportPageCount = 3,
                // A released swipe settles on the same spring as the button.
                flingBehavior = PagerDefaults.flingBehavior(
                    state = pagerState,
                    snapAnimationSpec = stepSpatial
                )
            ) { page ->
                // Steps change as screens do inside the app: a quarter-width
                // slide with a cross-fade, here following the finger. The pager
                // moves a page its full width, so three quarters are taken back.
                Box(
                    modifier = Modifier.graphicsLayer {
                        val offset = (page - pagerState.currentPage) - pagerState.currentPageOffsetFraction
                        alpha = 1f - offset.absoluteValue.coerceIn(0f, 1f)
                        // Only while in transit: at rest a shifted, invisible
                        // neighbour would lie over the current step and take its touches.
                        translationX = if (offset.absoluteValue < 1f) -offset * size.width * 0.75f else 0f
                    }
                ) {
                    OnboardingPage(page = page)
                }
            }

            // Bottom section: indicators + button
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 32.dp)
                    .padding(top = 16.dp, bottom = 32.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Animated dot indicators
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    repeat(4) { index ->
                        val isSelected = pagerState.currentPage == index
                        val dotWidth by animateDpAsState(
                            targetValue = if (isSelected) 24.dp else 8.dp,
                            animationSpec = MaterialTheme.motionScheme.fastSpatialSpec(),
                            label = "dotWidth"
                        )
                        val color by animateColorAsState(
                            targetValue = if (isSelected)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.outlineVariant,
                            animationSpec = MaterialTheme.motionScheme.defaultEffectsSpec(),
                            label = "dotColor"
                        )
                        Box(
                            modifier = Modifier
                                .height(8.dp)
                                .width(dotWidth)
                                .clip(MaterialTheme.shapes.extraLarge)
                                .background(color)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(20.dp))

                // One row for every step. On the last one the primary button
                // gives up half its width and Skip grows into the room, so the
                // buttons change shape in place instead of being swapped for
                // another layout. targetPage, so a tap on the button starts
                // this together with the step's own transition.
                val isScanPage = pagerState.targetPage == 3
                // The non-bouncy spring: a weight that overshot would push
                // the row past its bounds for a frame.
                val split by animateFloatAsState(
                    targetValue = if (isScanPage) 1f else 0f,
                    animationSpec = MotionScheme.standard().defaultSpatialSpec(),
                    label = "buttonSplit"
                )
                val labelEnter = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
                val labelExit = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                ) {
                    if (split > 0f) {
                        TextButton(
                            onClick = { onSkipPairing() },
                            enabled = isScanPage,
                            shapes = ButtonDefaults.shapes(),
                            modifier = Modifier
                                .weight(split.coerceAtLeast(0.001f))
                                .fillMaxHeight()
                                .graphicsLayer { alpha = split.coerceIn(0f, 1f) }
                        ) {
                            Text(
                                text = stringResource(R.string.pairing_skip),
                                style = MaterialTheme.typography.labelLarge,
                                maxLines = 1,
                                softWrap = false
                            )
                        }
                        Spacer(modifier = Modifier.width(12.dp * split.coerceIn(0f, 1f)))
                    }
                    // Standard shapes: the press morph every button inside the app has.
                    Button(
                        onClick = {
                            if (isScanPage) {
                                onScanQr()
                            } else {
                                coroutineScope.launch {
                                    pagerState.animateScrollToPage(
                                        pagerState.currentPage + 1,
                                        animationSpec = stepSpatial
                                    )
                                }
                            }
                        },
                        shapes = ButtonDefaults.shapes(),
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                    ) {
                        AnimatedContent(
                            targetState = isScanPage,
                            // No size transform: animated, it clipped the longer
                            // label and revealed it letter by letter.
                            transitionSpec = { (fadeIn(labelEnter) togetherWith fadeOut(labelExit)) using null },
                            contentAlignment = Alignment.Center,
                            label = "buttonLabel"
                        ) { scan ->
                            Text(
                                text = stringResource(if (scan) R.string.pairing_scan_title else R.string.onboarding_next),
                                style = MaterialTheme.typography.labelLarge,
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun OnboardingPage(page: Int) {
    when (page) {
        0 -> WelcomePage()
        1 -> HowItWorksPage()
        2 -> PermissionsPage()
        else -> ScanPage()
    }
}

@Composable
private fun WelcomePage() {
    val scrollState = rememberScrollState()
    ScrollLimitHaptics(scrollState)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(horizontal = 32.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(32.dp))
        androidx.compose.foundation.layout.Box(
            modifier = Modifier
                .size(140.dp)
                .clip(MaterialShapes.Cookie12Sided.toShape())
        ) {
            Image(
                painter = painterResource(R.drawable.ic_launcher_background),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
            Image(
                painter = painterResource(R.drawable.ic_launcher_foreground),
                contentDescription = "AirBridge",
                modifier = Modifier.fillMaxSize()
            )
        }

        Spacer(modifier = Modifier.height(32.dp))

        Text(
            text = stringResource(R.string.onboarding_welcome_title),
            style = MaterialTheme.typography.displaySmallEmphasized,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.onboarding_welcome_desc),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(32.dp))

        FeatureRow(icon = Icons.Rounded.ContentPaste, text = stringResource(R.string.onboarding_feature_clipboard), shape = MaterialShapes.Cookie9Sided)
        Spacer(modifier = Modifier.height(16.dp))
        FeatureRow(icon = Icons.AutoMirrored.Rounded.InsertDriveFile, text = stringResource(R.string.onboarding_feature_files), shape = MaterialShapes.Clover4Leaf)
        Spacer(modifier = Modifier.height(16.dp))
        FeatureRow(icon = Icons.AutoMirrored.Rounded.ScreenShare, text = stringResource(R.string.onboarding_feature_mirror), shape = MaterialShapes.Sunny)
        Spacer(modifier = Modifier.height(16.dp))
        FeatureRow(icon = Icons.Rounded.Notifications, text = stringResource(R.string.onboarding_feature_notifications), shape = MaterialShapes.Flower)
        Spacer(modifier = Modifier.height(16.dp))
        FeatureRow(icon = Icons.Rounded.AutoAwesome, text = stringResource(R.string.onboarding_feature_more), shape = MaterialShapes.Gem)
    }
}

@Composable
private fun HowItWorksPage() {
    val scrollState = rememberScrollState()
    ScrollLimitHaptics(scrollState)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(horizontal = 32.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(32.dp))
        WifiSymbol()

        Spacer(modifier = Modifier.height(32.dp))

        Text(
            text = stringResource(R.string.onboarding_connect_title),
            style = MaterialTheme.typography.displaySmallEmphasized,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.onboarding_connect_desc),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(32.dp))

        NumberedRow(number = "1", text = stringResource(R.string.onboarding_how_wifi), shape = MaterialShapes.Sunny)
        Spacer(modifier = Modifier.height(16.dp))
        NumberedRow(number = "2", text = stringResource(R.string.onboarding_how_auto), shape = MaterialShapes.Cookie6Sided)
        Spacer(modifier = Modifier.height(16.dp))
        NumberedRow(number = "3", text = stringResource(R.string.onboarding_how_local), shape = MaterialShapes.Clover4Leaf)
        Spacer(modifier = Modifier.height(16.dp))
        NumberedRow(number = "4", text = stringResource(R.string.onboarding_how_privacy), shape = MaterialShapes.Pentagon)
        Spacer(modifier = Modifier.height(16.dp))
        NumberedRow(number = "5", text = stringResource(R.string.onboarding_how_pairing), shape = MaterialShapes.Flower)
    }
}

// InlinedApi: POST_NOTIFICATIONS/READ_MEDIA_IMAGES (API 33) and
// ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION (API 30) are compile-time inlined
// string constants, safe to reference on minSdk 29; runtime use is guarded by the
// SDK_INT >= TIRAMISU check in checkPerm()/the launchers below.
@android.annotation.SuppressLint("InlinedApi")
@Composable
private fun PermissionsPage() {
    val context = LocalContext.current

    // Permission states
    fun checkPerm(perm: String): Boolean {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            context.checkSelfPermission(perm) == android.content.pm.PackageManager.PERMISSION_GRANTED
        } else true
    }

    var notificationsGranted by remember { mutableStateOf(checkPerm(android.Manifest.permission.POST_NOTIFICATIONS)) }
    var smsGranted by remember { mutableStateOf(checkPerm(android.Manifest.permission.READ_SMS)) }
    var photosGranted by remember { mutableStateOf(checkPerm(android.Manifest.permission.READ_MEDIA_IMAGES)) }
    var contactsGranted by remember { mutableStateOf(checkPerm(android.Manifest.permission.READ_CONTACTS)) }
    var hasFilesGrant by remember { mutableStateOf(isAllFilesAccessGranted()) }

    val notifLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { notificationsGranted = it }
    val smsLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        smsGranted = results[android.Manifest.permission.READ_SMS] == true
    }
    val photosLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { photosGranted = it }
    val contactsLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { contactsGranted = it }
    val filesLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        hasFilesGrant = isAllFilesAccessGranted()
    }
    // Optional (mirror only): lets the Mac start screen mirroring while the app
    // is in the background. Not part of `allGranted` so it never blocks onboarding.
    var overlayGranted by remember { mutableStateOf(Settings.canDrawOverlays(context)) }
    val overlayLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        overlayGranted = Settings.canDrawOverlays(context)
    }

    // Notification listener: optional (mirror notifications to Mac). Not part of `allGranted`.
    var notifListenerGranted by remember { mutableStateOf(isNotificationListenerEnabled(context)) }
    val notifListenerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        notifListenerGranted = isNotificationListenerEnabled(context)
    }

    // Phone: optional (incoming calls on the Mac). Not part of `allGranted`.
    var callsGranted by remember { mutableStateOf(callPermissionsGranted(context)) }
    val callsLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        callsGranted = callPermissionsGranted(context)
    }

    // Accessibility: optional (control phone from Mac during mirroring). Not part of `allGranted`.
    var accessibilityGranted by remember { mutableStateOf(isMirrorAccessibilityEnabled(context)) }
    val accessibilityLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        accessibilityGranted = isMirrorAccessibilityEnabled(context)
    }

    val allGranted = notificationsGranted && smsGranted && photosGranted && contactsGranted && hasFilesGrant

    // Granted or revoked in the system settings while away: read everything
    // again on return, whichever screen the grant was made on.
    androidx.lifecycle.compose.LifecycleResumeEffect(Unit) {
        notificationsGranted = checkPerm(android.Manifest.permission.POST_NOTIFICATIONS)
        smsGranted = checkPerm(android.Manifest.permission.READ_SMS)
        photosGranted = checkPerm(android.Manifest.permission.READ_MEDIA_IMAGES)
        contactsGranted = checkPerm(android.Manifest.permission.READ_CONTACTS)
        hasFilesGrant = isAllFilesAccessGranted()
        overlayGranted = Settings.canDrawOverlays(context)
        notifListenerGranted = isNotificationListenerEnabled(context)
        callsGranted = callPermissionsGranted(context)
        accessibilityGranted = isMirrorAccessibilityEnabled(context)
        onPauseOrDispose { }
    }

    val essential = listOf(
        PermissionEntry(
            icon = Icons.Rounded.Notifications,
            title = stringResource(R.string.onboarding_perm_notifications_desc),
            why = stringResource(R.string.onboarding_perm_notifications_why),
            granted = notificationsGranted,
            onRequest = {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    notifLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
                }
            }
        ),
        PermissionEntry(
            icon = Icons.Rounded.ChatBubble,
            title = stringResource(R.string.onboarding_perm_sms_desc),
            why = stringResource(R.string.onboarding_perm_sms_why),
            granted = smsGranted,
            onRequest = {
                smsLauncher.launch(arrayOf(
                    android.Manifest.permission.READ_SMS,
                    android.Manifest.permission.SEND_SMS
                ))
            }
        ),
        PermissionEntry(
            icon = Icons.Rounded.Photo,
            title = stringResource(R.string.onboarding_perm_photos_desc),
            why = stringResource(R.string.onboarding_perm_photos_why),
            granted = photosGranted,
            onRequest = {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    photosLauncher.launch(android.Manifest.permission.READ_MEDIA_IMAGES)
                }
            }
        ),
        PermissionEntry(
            icon = Icons.Rounded.Contacts,
            title = stringResource(R.string.onboarding_perm_contacts_desc),
            why = stringResource(R.string.onboarding_perm_contacts_why),
            granted = contactsGranted,
            onRequest = { contactsLauncher.launch(android.Manifest.permission.READ_CONTACTS) }
        ),
        PermissionEntry(
            icon = Icons.AutoMirrored.Rounded.InsertDriveFile,
            title = stringResource(R.string.onboarding_perm_files_desc),
            why = stringResource(R.string.onboarding_perm_files_why),
            granted = hasFilesGrant,
            onRequest = {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.fromParts("package", context.packageName, null)
                }
                filesLauncher.launch(intent)
            }
        ),
    )
    // Optional: none of these is part of `allGranted`.
    val optional = listOf(
        PermissionEntry(
            icon = Icons.Rounded.Notifications,
            title = stringResource(R.string.onboarding_perm_notiflistener_desc),
            why = stringResource(R.string.onboarding_perm_notiflistener_why),
            granted = notifListenerGranted,
            onRequest = {
                notifListenerLauncher.launch(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }
        ),
        PermissionEntry(
            icon = Icons.Rounded.Call,
            title = stringResource(R.string.onboarding_perm_calls_desc),
            // Settings explains this permission at length; a step of setup gets one line.
            why = stringResource(R.string.onboarding_perm_calls_short),
            granted = callsGranted,
            onRequest = { callsLauncher.launch(CALL_PERMISSIONS) }
        ),
        PermissionEntry(
            icon = Icons.Rounded.Tv,
            title = stringResource(R.string.onboarding_perm_overlay_desc),
            why = stringResource(R.string.onboarding_perm_overlay_why),
            granted = overlayGranted,
            onRequest = {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.fromParts("package", context.packageName, null)
                )
                overlayLauncher.launch(intent)
            }
        ),
        PermissionEntry(
            icon = Icons.Rounded.TouchApp,
            title = stringResource(R.string.onboarding_perm_accessibility_desc),
            why = stringResource(R.string.onboarding_perm_accessibility_why),
            granted = accessibilityGranted,
            onRequest = {
                accessibilityLauncher.launch(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }
        ),
    )

    val scrollState = rememberScrollState()
    ScrollLimitHaptics(scrollState)
    // The page's own 16 dp gutter, as on the pages inside the app: the two
    // cards run the full width, the centred text keeps the 32 dp of the other steps.
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(horizontal = 16.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(32.dp))
        Box(
            modifier = Modifier
                .size(140.dp)
                .clip(MaterialShapes.Clover8Leaf.toShape())
                .background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = if (allGranted) Icons.Rounded.Check else Icons.Rounded.Lock,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = if (allGranted) MaterialTheme.colorScheme.success else MaterialTheme.colorScheme.primary
            )
        }

        Spacer(modifier = Modifier.height(32.dp))

        Text(
            text = stringResource(R.string.onboarding_permissions_title),
            style = MaterialTheme.typography.displaySmallEmphasized,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.onboarding_permissions_desc),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 16.dp)
        )

        Spacer(modifier = Modifier.height(24.dp))

        PermissionGroup(
            header = stringResource(R.string.onboarding_perm_essential_header),
            entries = essential
        )
        Spacer(modifier = Modifier.height(16.dp))
        PermissionGroup(
            header = stringResource(R.string.onboarding_perm_optional_header),
            entries = optional
        )
    }
}

private class PermissionEntry(
    val icon: ImageVector,
    val title: String,
    val why: String,
    val granted: Boolean,
    val onRequest: () -> Unit,
)

/**
 * A card of permissions built as the cards in Settings are: a header, one
 * list item per permission and a divider between them. A row is tapped to
 * grant its permission and ends in a chevron until then, in a check after,
 * the same as the Phone permission row in Settings.
 */
@Composable
private fun PermissionGroup(header: String, entries: List<PermissionEntry>) {
    val stateEnterFade = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
    val stateEnterScale = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
    val stateExitFade = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
    PageCard(modifier = Modifier.fillMaxWidth()) {
        CardHeader(header)
        entries.forEachIndexed { index, entry ->
            if (index > 0) HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
            ListItem(
                verticalAlignment = Alignment.CenterVertically,
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                modifier = if (entry.granted) Modifier else Modifier.clickable(onClick = entry.onRequest),
                leadingContent = {
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(MaterialShapes.Cookie7Sided.toShape())
                            .background(MaterialTheme.colorScheme.primaryContainer),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = entry.icon,
                            contentDescription = null,
                            modifier = Modifier.size(22.dp),
                            tint = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                    }
                },
                content = { Text(entry.title) },
                supportingContent = { Text(entry.why) },
                trailingContent = {
                    AnimatedContent(
                        targetState = entry.granted,
                        transitionSpec = {
                            (fadeIn(stateEnterFade) + scaleIn(initialScale = 0.6f, animationSpec = stateEnterScale)) togetherWith
                                fadeOut(stateExitFade)
                        },
                        label = "permissionState"
                    ) { granted ->
                        if (granted) {
                            Icon(
                                Icons.Rounded.Check,
                                contentDescription = stringResource(R.string.onboarding_perm_granted_short),
                                tint = MaterialTheme.colorScheme.success
                            )
                        } else {
                            Icon(
                                Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                },
            )
        }
    }
}

@Composable
private fun ScanPage() {
    val scrollState = rememberScrollState()
    ScrollLimitHaptics(scrollState)
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(horizontal = 32.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(32.dp))
        QrSymbol()

        Spacer(modifier = Modifier.height(32.dp))

        Text(
            text = stringResource(R.string.pairing_scan_title),
            style = MaterialTheme.typography.displaySmallEmphasized,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.pairing_scan_desc),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, text: String, shape: RoundedPolygon) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(shape.toShape())
                .background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp)
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}

@Composable
private fun NumberedRow(number: String, text: String, shape: RoundedPolygon) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(shape.toShape())
                .background(MaterialTheme.colorScheme.primary),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = number,
                style = MaterialTheme.typography.labelMediumEmphasized,
                color = MaterialTheme.colorScheme.onPrimary,
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(top = 6.dp)
        )
    }
}

@Composable
private fun WifiSymbol() {
    Box(
        modifier = Modifier
            .size(140.dp)
            .clip(MaterialShapes.Cookie9Sided.toShape())
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Rounded.Wifi,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(64.dp)
        )
    }
}

@Composable
private fun QrSymbol() {
    Box(
        modifier = Modifier
            .size(140.dp)
            .clip(MaterialShapes.Sunny.toShape())
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Rounded.QrCodeScanner,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.size(64.dp)
        )
    }
}

/** Czy Airbridge ma włączony dostęp do powiadomień (notification listener) w ustawieniach systemu. */
fun isNotificationListenerEnabled(context: android.content.Context): Boolean {
    val flat = android.provider.Settings.Secure.getString(
        context.contentResolver, "enabled_notification_listeners"
    ) ?: return false
    val pkg = context.packageName
    return flat.split(":").any { it.startsWith("$pkg/") }
}

/** Czy usługa dostępności mirrora (sterowanie telefonem z Maca) jest włączona. */
fun isMirrorAccessibilityEnabled(context: android.content.Context): Boolean {
    val flat = android.provider.Settings.Secure.getString(
        context.contentResolver, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
    )
    val comp = "${context.packageName}/${context.packageName}.mirror.MirrorAccessibilityService"
    return com.airbridge.mirror.accessibilityServiceEnabled(flat, comp)
}

/** The Phone group: tell a ringing call from an ongoing one, and answer it from the Mac. */
internal val CALL_PERMISSIONS = arrayOf(
    android.Manifest.permission.READ_PHONE_STATE,
    android.Manifest.permission.ANSWER_PHONE_CALLS,
)

internal fun callPermissionsGranted(context: android.content.Context): Boolean = CALL_PERMISSIONS.all {
    context.checkSelfPermission(it) == android.content.pm.PackageManager.PERMISSION_GRANTED
}
