package com.airbridge.ui

import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp

/**
 * A full screen with a stock top app bar: the bar is pinned and takes the
 * scrolled container colour once content runs under it. Content receives the
 * bar height as [topInset] so it can reserve that space itself.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TopBarScreen(
    title: String,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable (topInset: Dp) -> Unit,
) {
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior()
    Scaffold(
        containerColor = MaterialTheme.colorScheme.pageBackground,
        modifier = Modifier.fillMaxSize().nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            TopAppBar(
                title = { Text(title, color = MaterialTheme.colorScheme.pageTitleColor, fontWeight = FontWeight(450)) },
                navigationIcon = navigationIcon,
                actions = actions,
                colors = pageTopAppBarColors(),
                scrollBehavior = scrollBehavior,
            )
        }
    ) { innerPadding ->
        content(innerPadding.calculateTopPadding())
    }
}
