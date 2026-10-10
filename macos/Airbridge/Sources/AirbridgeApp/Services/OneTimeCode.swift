import AppKit

/// Finds a one-time code (a verification code, PIN, password reset code) in
/// a message, the way iOS offers "Copy code": 4–8 digits, also written as
/// "123 456" or "123-456", only in a message that says it carries a code, so
/// phone numbers, amounts and dates aren't picked up.
enum OneTimeCode {
    private static let keywords = [
        "kod", "code", "pin", "hasło", "haslo", "weryfikac", "verification", "passcode", "otp", "jednorazow",
    ]

    /// Digits standing alone: 4–8 of them, or two groups of three.
    private static let candidate = try! NSRegularExpression(
        pattern: #"(?<![\d.,:/+])(\d{3}[ -]\d{3}|\d{4,8})(?![\d.,:/]\d)"#
    )

    static func find(in text: String) -> String? {
        let lower = text.lowercased()
        guard keywords.contains(where: { lower.contains($0) }) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in candidate.matches(in: text, range: range) {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let digits = text[r].filter(\.isNumber)
            // A year on its own ("2026") is a date, not a code.
            if digits.count == 4, let year = Int(digits), (1990...2100).contains(year) { continue }
            return String(digits)
        }
        return nil
    }

    static func copy(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}
