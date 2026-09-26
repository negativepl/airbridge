package com.airbridge.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.statusBars
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState

/**
 * A full screen with the same glass top bar as the tabs: the content runs
 * under the bar (it gets the bar height as [topInset] to reserve), the bar
 * blurs what scrolls beneath and carries the edge light on its bottom edge.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlassTopBarScreen(
    title: String,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {},
    content: @Composable (topInset: Dp) -> Unit,
) {
    val hazeState = rememberHazeState()
    val topInset = TopAppBarDefaults.TopAppBarExpandedHeight +
        WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surfaceContainer) {
        Box(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.fillMaxSize().hazeSource(hazeState)) { content(topInset) }
            key(MaterialTheme.colorScheme.surfaceContainer) {
                TopAppBar(
                    title = { Text(title) },
                    navigationIcon = navigationIcon,
                    actions = actions,
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .glassBar(hazeState, MaterialTheme.colorScheme.surfaceContainer)
                        .bottomEdgeLight()
                )
            }
        }
    }
}
