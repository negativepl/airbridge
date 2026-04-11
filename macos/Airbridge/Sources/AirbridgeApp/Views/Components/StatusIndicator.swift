import SwiftUI

/// Unified connection/state indicator with built-in symbol effects.
///
/// Replaces manual `Circle().fill(...)` patterns and ensures every status
/// display in the app animates consistently and respects reduce-motion.
struct StatusIndicator: View {
    enum State: Equatable {
        case connected
        case disconnected
        case connecting
        case error
    }

    let state: State
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch state {
            case .connected:
                Circle()
                    .fill(.green)
                    .frame(width: size * 0.85, height: size * 0.85)

            case .disconnected:
                Circle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: size * 0.85, height: size * 0.85)

            case .connecting:
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(.orange)
                    .symbolEffect(.variableColor.cumulative.reversing, options: .repeating)

            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(.red)
                    .symbolEffect(.bounce, value: state)
            }
        }
        .frame(width: size, height: size)
        .contentTransition(.symbolEffect(.replace))
    }
}
