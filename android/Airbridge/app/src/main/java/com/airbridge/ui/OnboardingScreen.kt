package com.airbridge.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.ChatBubble
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Contacts
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Photo
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.foundation.Image
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.airbridge.R
import kotlinx.coroutines.launch

private val PillShape = RoundedCornerShape(50)

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
                    .padding(horizontal = 32.dp, vertical = 48.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Animated dot indicators — pill for selected, circle for unselected
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    repeat(4) { index ->
                        val isSelected = pagerState.currentPage == index
                        val dotWidth by animateDpAsState(
                            targetValue = if (isSelected) 24.dp else 8.dp,
                            animationSpec = spring(
                                dampingRatio = 0.7f,
                                stiffness = 300f
                            ),
                            label = "dotWidth"
                        )
                        val color by animateColorAsState(
                            targetValue = if (isSelected)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.outlineVariant,
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

                Spacer(modifier = Modifier.height(32.dp))

                if (pagerState.currentPage == 3) {
                    // Scan QR button (page 3)
                    var pressed by remember { mutableStateOf(false) }
                    val buttonScale by animateFloatAsState(
                        targetValue = if (pressed) 0.95f else 1f,
                        animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
                        label = "btnScale"
                    )
                    FilledTonalButton(
                        onClick = { onScanQr() },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp)
                            .scale(buttonScale)
                            .pointerInput(Unit) {
                                detectTapGestures(
                                    onPress = {
                                        pressed = true
                                        tryAwaitRelease()
                                        pressed = false
                                    }
                                )
                            },
                        shape = PillShape
                    ) {
                        Text(
                            text = stringResource(R.string.pairing_scan_title),
                            style = MaterialTheme.typography.labelLarge
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    TextButton(onClick = { onSkipPairing() }) {
                        Text(
                            text = stringResource(R.string.pairing_skip),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    // "Next" — FilledTonalButton with pill shape and press feedback
                    var pressed by remember { mutableStateOf(false) }
                    val buttonScale by animateFloatAsState(
                        targetValue = if (pressed) 0.95f else 1f,
                        animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
                        label = "btnScale"
                    )
                    FilledTonalButton(
                        onClick = {
                            coroutineScope.launch {
                                pagerState.animateScrollToPage(pagerState.currentPage + 1)
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp)
                            .scale(buttonScale)
                            .pointerInput(Unit) {
                                detectTapGestures(
                                    onPress = {
                                        pressed = true
                                        tryAwaitRelease()
                                        pressed = false
                                    }
                                )
                            },
                        shape = PillShape
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
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Image(
            painter = painterResource(R.drawable.logo_airbridge),
            contentDescription = "Airbridge",
            modifier = Modifier
                .size(220.dp)
                .clip(RoundedCornerShape(44.dp)),
            contentScale = ContentScale.Crop
        )

        Spacer(modifier = Modifier.height(24.dp))

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

        FeatureRow(icon = Icons.Rounded.ContentPaste, text = stringResource(R.string.onboarding_feature_clipboard))
        Spacer(modifier = Modifier.height(16.dp))
        FeatureRow(icon = Icons.AutoMirrored.Rounded.InsertDriveFile, text = stringResource(R.string.onboarding_feature_files))
        Spacer(modifier = Modifier.height(16.dp))
        FeatureRow(icon = Icons.Rounded.Lock, text = stringResource(R.string.onboarding_feature_local))
    }
}

@Composable
private fun HowItWorksPage() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        WifiSymbol()

        Spacer(modifier = Modifier.height(40.dp))

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

        NumberedRow(number = "1", text = stringResource(R.string.onboarding_how_wifi))
        Spacer(modifier = Modifier.height(16.dp))
        NumberedRow(number = "2", text = stringResource(R.string.onboarding_how_auto))
        Spacer(modifier = Modifier.height(16.dp))
        NumberedRow(number = "3", text = stringResource(R.string.onboarding_how_bg))
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

    val notifLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { notificationsGranted = it }
    val smsLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        smsGranted = results[android.Manifest.permission.READ_SMS] == true
    }
    val photosLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { photosGranted = it }
    val contactsLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { contactsGranted = it }

    val allGranted = notificationsGranted && smsGranted && photosGranted && contactsGranted

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(140.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = if (allGranted) Icons.Rounded.Check else Icons.Rounded.Lock,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = if (allGranted) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary
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
            granted = contactsGranted,
            onRequest = { contactsLauncher.launch(android.Manifest.permission.READ_CONTACTS) }
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
                    tint = Color(0xFF4CAF50),
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = stringResource(R.string.onboarding_perm_all_granted),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color(0xFF4CAF50),
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
    granted: Boolean,
    onRequest: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(22.dp),
            tint = if (granted) Color(0xFF4CAF50) else MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f)
        )
        if (granted) {
            Icon(
                imageVector = Icons.Rounded.Check,
                contentDescription = null,
                tint = Color(0xFF4CAF50),
                modifier = Modifier.size(20.dp)
            )
        } else {
            FilledTonalButton(
                onClick = onRequest,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 0.dp),
                modifier = Modifier.height(32.dp)
            ) {
                Text(
                    text = stringResource(R.string.onboarding_perm_allow_btn),
                    style = MaterialTheme.typography.labelMedium
                )
            }
        }
    }
}

@Composable
private fun ScanPage() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        QrSymbol()

        Spacer(modifier = Modifier.height(40.dp))

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
private fun FeatureRow(icon: ImageVector, text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
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
private fun NumberedRow(number: String, text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
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
private fun BridgeSymbol() {
    val primary = MaterialTheme.colorScheme.primary
    val primaryContainer = MaterialTheme.colorScheme.primaryContainer

    val infiniteTransition = rememberInfiniteTransition(label = "bridgePulse")
    val scale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.06f,
        animationSpec = infiniteRepeatable(
            animation = tween(2000),
            repeatMode = RepeatMode.Reverse
        ),
        label = "bridgeScale"
    )

    Box(
        modifier = Modifier
            .size(180.dp)
            .scale(scale)
            .clip(CircleShape)
            .background(primaryContainer),
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.size(100.dp)) {
            val w = size.width
            val h = size.height
            val thick = 7f
            val thin = 3f

            // Bridge arch
            val archPath = Path().apply {
                moveTo(w * 0.05f, h * 0.58f)
                quadraticBezierTo(w * 0.5f, h * 0.08f, w * 0.95f, h * 0.58f)
            }
            drawPath(archPath, color = primary, style = Stroke(width = thick, cap = StrokeCap.Round))

            // Road (horizontal line)
            drawLine(
                color = primary,
                start = Offset(w * 0.0f, h * 0.70f),
                end = Offset(w * 1.0f, h * 0.70f),
                strokeWidth = thick,
                cap = StrokeCap.Round
            )

            // Center pillar (tallest)
            drawLine(
                color = primary,
                start = Offset(w * 0.5f, h * 0.16f),
                end = Offset(w * 0.5f, h * 0.70f),
                strokeWidth = thick,
                cap = StrokeCap.Round
            )

            // Left pillar
            drawLine(
                color = primary,
                start = Offset(w * 0.25f, h * 0.38f),
                end = Offset(w * 0.25f, h * 0.70f),
                strokeWidth = thick,
                cap = StrokeCap.Round
            )

            // Cable lines (suspension cables from center pillar)
            val cableColor = primary.copy(alpha = 0.4f)
            drawLine(cableColor, Offset(w * 0.5f, h * 0.16f), Offset(w * 0.18f, h * 0.70f), thin, StrokeCap.Round)
            drawLine(cableColor, Offset(w * 0.5f, h * 0.16f), Offset(w * 0.36f, h * 0.70f), thin, StrokeCap.Round)
            drawLine(cableColor, Offset(w * 0.5f, h * 0.16f), Offset(w * 0.64f, h * 0.70f), thin, StrokeCap.Round)
            drawLine(cableColor, Offset(w * 0.5f, h * 0.16f), Offset(w * 0.82f, h * 0.70f), thin, StrokeCap.Round)
        }
    }
}

@Composable
private fun WifiSymbol() {
    val primary = MaterialTheme.colorScheme.primary
    val primaryContainer = MaterialTheme.colorScheme.primaryContainer

    Box(
        modifier = Modifier
            .size(140.dp)
            .clip(CircleShape)
            .background(primaryContainer),
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.size(64.dp)) {
            val cx = size.width / 2f
            val bottom = size.height * 0.78f
            val strokeW = 5f

            // Draw three arcs from bottom center
            for (i in 0..2) {
                val radius = 14f + i * 16f
                drawArc(
                    color = primary,
                    startAngle = 225f,
                    sweepAngle = 90f,
                    useCenter = false,
                    topLeft = Offset(cx - radius, bottom - radius * 2 + radius * 0.3f),
                    size = androidx.compose.ui.geometry.Size(radius * 2, radius * 2),
                    style = Stroke(width = strokeW, cap = StrokeCap.Round)
                )
            }
            // Dot at the bottom
            drawCircle(
                color = primary,
                radius = 4f,
                center = Offset(cx, bottom)
            )
        }
    }
}

@Composable
private fun QrSymbol() {
    val primary = MaterialTheme.colorScheme.primary
    val primaryContainer = MaterialTheme.colorScheme.primaryContainer

    Box(
        modifier = Modifier
            .size(140.dp)
            .clip(CircleShape)
            .background(primaryContainer),
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.size(64.dp)) {
            val w = size.width
            val h = size.height
            val strokeW = 5f

            // QR code corner brackets
            drawLine(primary, Offset(w * 0.1f, w * 0.1f), Offset(w * 0.35f, w * 0.1f), strokeW, StrokeCap.Round)
            drawLine(primary, Offset(w * 0.1f, w * 0.1f), Offset(w * 0.1f, w * 0.35f), strokeW, StrokeCap.Round)
            drawLine(primary, Offset(w * 0.65f, w * 0.1f), Offset(w * 0.9f, w * 0.1f), strokeW, StrokeCap.Round)
            drawLine(primary, Offset(w * 0.9f, w * 0.1f), Offset(w * 0.9f, w * 0.35f), strokeW, StrokeCap.Round)
            drawLine(primary, Offset(w * 0.1f, h * 0.65f), Offset(w * 0.1f, h * 0.9f), strokeW, StrokeCap.Round)
            drawLine(primary, Offset(w * 0.1f, h * 0.9f), Offset(w * 0.35f, h * 0.9f), strokeW, StrokeCap.Round)
            drawLine(primary, Offset(w * 0.65f, h * 0.9f), Offset(w * 0.9f, h * 0.9f), strokeW, StrokeCap.Round)
            drawLine(primary, Offset(w * 0.9f, h * 0.65f), Offset(w * 0.9f, h * 0.9f), strokeW, StrokeCap.Round)
            drawCircle(primary, radius = w * 0.06f, center = Offset(w * 0.5f, h * 0.5f))
        }
    }
}

@Composable
private fun CheckmarkSymbol() {
    val primary = MaterialTheme.colorScheme.primary
    val primaryContainer = MaterialTheme.colorScheme.primaryContainer

    // Scale-in animation
    val scale by animateFloatAsState(
        targetValue = 1f,
        animationSpec = spring(dampingRatio = 0.5f, stiffness = 200f),
        label = "checkScale"
    )

    Box(
        modifier = Modifier
            .size(140.dp)
            .scale(scale)
            .clip(CircleShape)
            .background(primaryContainer),
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.size(56.dp)) {
            val path = Path().apply {
                moveTo(size.width * 0.2f, size.height * 0.5f)
                lineTo(size.width * 0.42f, size.height * 0.72f)
                lineTo(size.width * 0.8f, size.height * 0.28f)
            }
            drawPath(
                path = path,
                color = primary,
                style = Stroke(width = 6f, cap = StrokeCap.Round)
            )
        }
    }
}
