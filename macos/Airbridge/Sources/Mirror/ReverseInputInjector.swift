import Foundation
import CoreGraphics

/// Injects pointer / scroll events onto a specific display, driven by the phone
/// in reverse-control mode. Requires the app to be trusted for Accessibility.
public enum ReverseInputInjector {

    /// type: 0 = move, 1 = down, 2 = up, 3 = drag, 4 = right-click (down+up).
    /// Coords are normalized 0..1 within the captured display.
    public static func injectPointer(type: UInt8, xNorm: Float, yNorm: Float, displayID: CGDirectDisplayID) {
        let bounds = CGDisplayBounds(displayID)
        let point = CGPoint(
            x: bounds.origin.x + CGFloat(max(0, min(1, xNorm))) * bounds.width,
            y: bounds.origin.y + CGFloat(max(0, min(1, yNorm))) * bounds.height
        )
        if type == 4 {
            post(.rightMouseDown, point, .right)
            post(.rightMouseUp, point, .right)
            return
        }
        let eventType: CGEventType
        switch type {
        case 1:  eventType = .leftMouseDown
        case 2:  eventType = .leftMouseUp
        case 3:  eventType = .leftMouseDragged
        default: eventType = .mouseMoved
        }
        post(eventType, point, .left)
    }

    private static func post(_ type: CGEventType, _ point: CGPoint, _ button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
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

    // MARK: - Keyboard

    /// Type a Unicode string as-is (no modifiers).
    public static func injectText(_ text: String) {
        var chars = Array(text.utf16)
        guard !chars.isEmpty else { return }
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown) else { continue }
            event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// A special key press (down+up). `code` is our cross-platform key id;
    /// modifiers bitmask: 1=shift, 2=ctrl, 4=alt, 8=cmd.
    public static func injectKey(code: UInt16, modifiers: UInt8) {
        guard let virtualKey = keyMap[code] else { return }
        var flags: CGEventFlags = []
        if modifiers & 1 != 0 { flags.insert(.maskShift) }
        if modifiers & 2 != 0 { flags.insert(.maskControl) }
        if modifiers & 4 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 8 != 0 { flags.insert(.maskCommand) }
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: keyDown) else { continue }
            event.flags = flags
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// Our key ids -> macOS virtual key codes (kVK_*).
    private static let keyMap: [UInt16: CGKeyCode] = [
        1: 51,    // backspace (kVK_Delete)
        2: 36,    // return
        3: 48,    // tab
        4: 53,    // escape
        5: 123,   // left arrow
        6: 124,   // right arrow
        7: 126,   // up arrow
        8: 125,   // down arrow
        9: 117,   // forward delete
        10: 115,  // home
        11: 119,  // end
    ]
}
