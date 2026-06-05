import SwiftUI

/// Centralized text scale. Replaces scattered `.font(.system(size:))` calls
/// with named roles so the whole app shares one type ramp — change the scale
/// in one place instead of hunting magic numbers across every view.
///
/// Sizes are preserved 1:1 from the original inline values: this is a rename
/// to named roles, NOT a visual change.
///
/// Usage:
///
///     Text("Heading").font(.ab(.title2, weight: .semibold))
///     Text("Body row").font(.ab(.body))
///     Text("Timestamp").font(.ab(.caption))
///
/// One-off decorative icon glyph sizes (SF Symbols at 28/44/96 pt etc.) stay
/// inline — they're contextual per-screen, not part of the shared text ramp.
extension Font {
    enum ABRole {
        case caption2     // 10 — fine print, footers
        case caption      // 11 — timestamps
        case footnote     // 12 — tertiary labels, hints
        case subheadline  // 13 — secondary body
        case body         // 14 — default body / row text
        case callout      // 15 — emphasized body, inputs
        case headline     // 16 — row titles
        case title3       // 18
        case title2       // 20 — empty-state titles

        var size: CGFloat {
            switch self {
            case .caption2: 10
            case .caption: 11
            case .footnote: 12
            case .subheadline: 13
            case .body: 14
            case .callout: 15
            case .headline: 16
            case .title3: 18
            case .title2: 20
            }
        }
    }

    /// Named text-scale role. Weight defaults to `.regular`; pass `weight:` to
    /// reuse a size at a heavier grade (the app uses .medium/.semibold/.bold).
    static func ab(_ role: ABRole, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: role.size, weight: weight, design: design)
    }

    // MARK: - Branded / display fonts

    /// Serif app name on the About window (30 pt).
    static let abAppName = Font.system(size: 30, weight: .regular, design: .serif)

    /// Serif hero name on the onboarding welcome page (56 pt).
    static let abHeroName = Font.system(size: 56, weight: .regular, design: .serif)

    /// Onboarding page titles (40 pt semibold).
    static let abPageTitle = Font.system(size: 40, weight: .semibold)
}
