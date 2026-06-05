import Foundation
import CoreGraphics

/// Injects pointer / scroll events onto a specific display, driven by the phone
/// in reverse-control mode. Requires the app to be trusted for Accessibility.
public enum ReverseInputInjector {

    /// type: 0 = move, 1 = down, 2 = up, 3 = drag. Coords are normalized 0..1
    /// within the captured display.
    public static func injectPointer(type: UInt8, xNorm: Float, yNorm: Float, displayID: CGDirectDisplayID) {
        let bounds = CGDisplayBounds(displayID)
        let point = CGPoint(
            x: bounds.origin.x + CGFloat(max(0, min(1, xNorm))) * bounds.width,
            y: bounds.origin.y + CGFloat(max(0, min(1, yNorm))) * bounds.height
        )
        let eventType: CGEventType
        switch type {
        case 1:  eventType = .leftMouseDown
        case 2:  eventType = .leftMouseUp
        case 3:  eventType = .leftMouseDragged
        default: eventType = .mouseMoved
        }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cgSessionEventTap)
    }

    /// Scroll wheel in pixels. Positive deltaY scrolls content down (natural).
    public static func injectScroll(deltaX: Float, deltaY: Float) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(-deltaY),   // wheel1 = vertical; negate so finger-down scrolls down
            wheel2: Int32(-deltaX),   // wheel2 = horizontal
            wheel3: 0
        ) else { return }
        event.post(tap: .cgSessionEventTap)
    }
}
