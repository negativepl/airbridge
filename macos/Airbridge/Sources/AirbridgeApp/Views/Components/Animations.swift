import SwiftUI

extension Animation {
    /// Fast, subtle spring. Use for state-change cards, toggles, appear/disappear.
    /// Response 0.4s, damping 0.85 — quick settle, minimal overshoot.
    static let airbridgeQuick = Animation.spring(response: 0.4, dampingFraction: 0.85)

    /// Slightly slower, mildly bouncy spring. Use for sheet transitions,
    /// popup morph, larger layout transitions.
    /// Response 0.55s, damping 0.75 — visible settle, small overshoot.
    static let airbridgeSmooth = Animation.spring(response: 0.55, dampingFraction: 0.75)

    /// Spring for popup state transitions (drop zone → waiting → transferring).
    /// Slight bounce at the end — the "delikatne odbicie" that makes content
    /// feel like it LANDS in place instead of just fading.
    /// Duration 0.6s, subtle extra bounce 0.12.
    static let airbridgeStateMorph = Animation.bouncy(duration: 0.6, extraBounce: 0.12)
}
