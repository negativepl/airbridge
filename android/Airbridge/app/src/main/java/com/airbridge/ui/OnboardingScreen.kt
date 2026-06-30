package com.airbridge.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.graphics.shapes.RoundedPolygon
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.ScreenShare
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.material.icons.rounded.ContentPaste
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
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import com.airbridge.R
import kotlinx.coroutines.launch

private val PillShape = RoundedCornerShape(50)

// "All files access" (MANAGE_EXTERNAL_STORAGE) only exists from API 30 (R). On API 29
// the method is absent — calling it would crash — and the grant is unobtainable, so the
// files feature is simply reported as ungranted there.
private fun isAllFilesAccessGranted(): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()

// "Next" page change: emphasized-easing tween, NOT a spring — a spring overshoots
// (bounces) at the end, which reads as broken next to a standard app screen
// transition. Google apps don't bounce between screens; this curve accelerates
// then settles smoothly with no overshoot.
private val PageScrollSpec = tween<Float>(
    durationMillis = 400,
    easing = CubicBezierEasing(0.2f, 0.0f, 0.0f, 1.0f)
)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun OnboardingScreen(
    onFinished: () -> Unit,
    onScanQr: () -> Unit,
    onSkipPairing: () -> Unit = onFinished
) {
    val pagerState = rememberPagerState(pageCount = { 4 })
    val coroutineScope = rememberCoroutineScope()

    Scaffold(
        containerColor = MaterialTheme.colorScheme.surface
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f)
            ) { page ->
                OnboardingPage(page = page)
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
                                .clip(PillShape)
                                .background(color)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(20.dp))

                val btnEnterFade = MaterialTheme.motionScheme.defaultEffectsSpec<Float>()
                val btnEnterScale = MaterialTheme.motionScheme.defaultSpatialSpec<Float>()
                val btnExitFade = MaterialTheme.motionScheme.fastEffectsSpec<Float>()
                val btnExitScale = MaterialTheme.motionScheme.fastSpatialSpec<Float>()
                AnimatedContent(
                    targetState = pagerState.currentPage == 3,
                    transitionSpec = {
                        (fadeIn(animationSpec = btnEnterFade) + scaleIn(initialScale = 0.95f, animationSpec = btnEnterScale))
                            .togetherWith(fadeOut(animationSpec = btnExitFade) + scaleOut(targetScale = 0.95f, animationSpec = btnExitScale))
                    },
                    label = "buttonTransition"
                ) { isScanPage ->
                if (isScanPage) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        TextButton(
                            onClick = { onSkipPairing() },
                            modifier = Modifier
                                .weight(1f)
                                .height(56.dp)
                        ) {
                            Text(
                                text = stringResource(R.string.pairing_skip),
                                style = MaterialTheme.typography.labelLarge
                            )
                        }
                        FilledTonalButton(
                            onClick = { onScanQr() },
                            modifier = Modifier
                                .weight(1f)
                                .height(56.dp)
                        ) {
                            Text(
                                text = stringResource(R.string.pairing_scan_title),
                                style = MaterialTheme.typography.labelLarge
                            )
                        }
                    }
                } else {
                    // "Next" — native FilledTonalButton; pressed feedback (state layer
                    // + Expressive shape) is built in, no hand-rolled scale needed.
                    FilledTonalButton(
                        onClick = {
                            coroutineScope.launch {
                                pagerState.animateScrollToPage(
                                    pagerState.currentPage + 1,
                                    animationSpec = PageScrollSpec
                                )
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.onboarding_next),
                            style = MaterialTheme.typography.labelLarge
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
            style = MaterialTheme.typography.displaySmall,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            fontWeight = FontWeight.Bold
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
            style = MaterialTheme.typography.displaySmall,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            fontWeight = FontWeight.Bold
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

    // Accessibility: optional (control phone from Mac during mirroring). Not part of `allGranted`.
    var accessibilityGranted by remember { mutableStateOf(isMirrorAccessibilityEnabled(context)) }
    val accessibilityLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        accessibilityGranted = isMirrorAccessibilityEnabled(context)
    }

    val allGranted = notificationsGranted && smsGranted && photosGranted && contactsGranted && hasFilesGrant

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
            style = MaterialTheme.typography.displaySmall,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.onboarding_permissions_desc),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Permission rows
        PermissionRow(
            icon = Icons.Rounded.Notifications,
            description = stringResource(R.string.onboarding_perm_notifications_desc),
            why = stringResource(R.string.onboarding_perm_notifications_why),
            granted = notificationsGranted,
            onRequest = {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    notifLauncher.launch(android.Manifest.permission.POST_NOTIFICATIONS)
                }
            }
        )
        Spacer(modifier = Modifier.height(10.dp))
        PermissionRow(
            icon = Icons.Rounded.ChatBubble,
            description = stringResource(R.string.onboarding_perm_sms_desc),
            why = stringResource(R.string.onboarding_perm_sms_why),
            granted = smsGranted,
            onRequest = {
                smsLauncher.launch(arrayOf(
                    android.Manifest.permission.READ_SMS,
                    android.Manifest.permission.SEND_SMS
                ))
            }
        )
        Spacer(modifier = Modifier.height(10.dp))
        PermissionRow(
            icon = Icons.Rounded.Photo,
            description = stringResource(R.string.onboarding_perm_photos_desc),
            why = stringResource(R.string.onboarding_perm_photos_why),
            granted = photosGranted,
            onRequest = {
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    photosLauncher.launch(android.Manifest.permission.READ_MEDIA_IMAGES)
                }
            }
        )
        Spacer(modifier = Modifier.height(10.dp))
        PermissionRow(
            icon = Icons.Rounded.Contacts,
            description = stringResource(R.string.onboarding_perm_contacts_desc),
            why = stringResource(R.string.onboarding_perm_contacts_why),
            granted = contactsGranted,
            onRequest = { contactsLauncher.launch(android.Manifest.permission.READ_CONTACTS) }
        )
        Spacer(modifier = Modifier.height(10.dp))
        PermissionRow(
            icon = Icons.AutoMirrored.Rounded.InsertDriveFile,
            description = stringResource(R.string.onboarding_perm_files_desc),
            why = stringResource(R.string.onboarding_perm_files_why),
            granted = hasFilesGrant,
            onRequest = {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.fromParts("package", context.packageName, null)
                }
                filesLauncher.launch(intent)
            }
        )
        Spacer(modifier = Modifier.height(10.dp))
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = stringResource(R.string.onboarding_perm_optional_header),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(8.dp))

        PermissionRow(
            icon = Icons.Rounded.Tv,
            description = stringResource(R.string.onboarding_perm_overlay_desc),
            why = stringResource(R.string.onboarding_perm_overlay_why),
            granted = overlayGranted,
            onRequest = {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.fromParts("package", context.packageName, null)
                )
                overlayLauncher.launch(intent)
            }
        )

        PermissionRow(
            icon = Icons.Rounded.Notifications,
            description = stringResource(R.string.onboarding_perm_notiflistener_desc),
            why = stringResource(R.string.onboarding_perm_notiflistener_why),
            granted = notifListenerGranted,
            onRequest = {
                notifListenerLauncher.launch(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }
        )

        PermissionRow(
            icon = Icons.Rounded.TouchApp,
            description = stringResource(R.string.onboarding_perm_accessibility_desc),
            why = stringResource(R.string.onboarding_perm_accessibility_why),
            granted = accessibilityGranted,
            onRequest = {
                accessibilityLauncher.launch(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }
        )

        if (allGranted) {
            Spacer(modifier = Modifier.height(20.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.success,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = stringResource(R.string.onboarding_perm_all_granted),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.success,
                    fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

@Composable
private fun PermissionRow(
    icon: ImageVector,
    description: String,
    why: String = "",
    granted: Boolean,
    onRequest: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(MaterialShapes.Cookie7Sided.toShape())
                        .background(MaterialTheme.colorScheme.primaryContainer),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        modifier = Modifier.size(22.dp),
                        tint = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
                Spacer(Modifier.width(16.dp))
                // Title + reason take the full row width — both the action and the
                // granted check sit on the row below, so nothing squeezes the text.
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        description,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    if (why.isNotEmpty()) {
                        Spacer(Modifier.height(2.dp))
                        Text(
                            why,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (granted) {
                    Icon(
                        imageVector = Icons.Rounded.Check,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.success,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        stringResource(R.string.onboarding_perm_granted_short),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.success
                    )
                } else {
                    FilledTonalButton(onClick = onRequest) {
                        Text(stringResource(R.string.onboarding_perm_allow_btn))
                    }
                }
            }
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
            style = MaterialTheme.typography.displaySmall,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
            fontWeight = FontWeight.Bold
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
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onPrimary,
                fontWeight = FontWeight.Bold
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
