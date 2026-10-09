package com.airbridge.ui

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * The stock [Card] as it sits on a page in this app: extraLarge corners and
 * the page's card colour (see [pageCardColors]). A pass-through of two theme
 * tokens, nothing more; everything else is the Material card.
 */
@Composable
fun PageCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = modifier,
        shape = MaterialTheme.shapes.extraLarge,
        colors = pageCardColors(),
        content = content,
    )
}

/** Clickable [PageCard]; same parameters as the clickable [Card]. */
@Composable
fun PageCard(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        shape = MaterialTheme.shapes.extraLarge,
        colors = pageCardColors(),
        content = content,
    )
}
