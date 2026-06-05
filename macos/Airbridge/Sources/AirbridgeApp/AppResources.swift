import Foundation

// SwiftPM's generated Bundle.module accessor hardcodes the developer's
// .build/ path as its fallback, so a distributed .app crashes on any other
// Mac at first access. We bypass it by shipping resources directly in the
// .app's main bundle and pointing lookups at Bundle.main.
enum AppResources {
    static let bundle: Bundle = .main
}
