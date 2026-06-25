package com.airbridge.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalView

/**
 * Plays a crisp haptic tick when [scrollState] crosses into a content edge — the
 * "wall" tap you feel on ColorOS when a list tops out or bottoms out.
 *
 * The platform's true scroll-limit haptic (ScrollFeedbackProvider) is a no-op
 * for touchscreen sources on One UI — it is the same framework path Samsung
 * chose not to wire up — so we trigger an explicit CONTEXT_CLICK instead, which
 * reliably fires and still honours the system haptic-feedback setting.
 *
 * Detection is purely positional: we watch the scroll offset and fire once when
 * it lands on an edge having come from off it. That covers BOTH ends and avoids
 * the timing races of gating on isScrollInProgress (which made the bottom edge
 * miss). Starting [previous] at the current value keeps the first frame silent.
 */
@Composable
fun ScrollLimitHaptics(scrollState: ScrollState) {
    val view = LocalView.current
    LaunchedEffect(scrollState) {
        var previous = scrollState.value
        snapshotFlow { scrollState.value }.collect { value ->
            val max = scrollState.maxValue
            if (max > 0) {
                val hitTop = value == 0 && previous > 0
                val hitBottom = value >= max && previous < max
                if (hitTop || hitBottom) {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                }
            }
            previous = value
        }
    }
}

/**
 * LazyColumn/LazyRow variant of [ScrollLimitHaptics]. A [ScrollState] tracks a
 * pixel offset, but a lazy list doesn't — so edges are detected via
 * `canScrollBackward`/`canScrollForward`, firing once when the list lands on an
 * edge having been able to scroll past it a moment earlier. Lists short enough to
 * not scroll start pinned to both edges and never transition, so they stay silent.
 */
@Composable
fun ScrollLimitHaptics(listState: LazyListState) {
    val view = LocalView.current
    LaunchedEffect(listState) {
        var prevTop = !listState.canScrollBackward
        var prevBottom = !listState.canScrollForward
        snapshotFlow { !listState.canScrollBackward to !listState.canScrollForward }
            .collect { (atTop, atBottom) ->
                if ((atTop && !prevTop) || (atBottom && !prevBottom)) {
                    view.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
                }
                prevTop = atTop
                prevBottom = atBottom
            }
    }
}
