import Foundation

enum NavigationItem: String, CaseIterable, Identifiable, Hashable {
    case home
    case history
    case send
    case gallery
    case messages
    case settings
    case about

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .history: return "clock.arrow.circlepath"
        case .send: return "paperplane.fill"
        case .gallery: return "photo.on.rectangle"
        case .messages: return "message.fill"
        case .settings: return "gearshape.fill"
        case .about: return "info.circle"
        }
    }

    var title: String {
        switch self {
        case .home: return L10n.isPL ? "Główna" : "Home"
        case .history: return L10n.isPL ? "Historia" : "History"
        case .send: return L10n.isPL ? "Wyślij" : "Send"
        case .gallery: return L10n.isPL ? "Galeria" : "Gallery"
        case .messages: return L10n.isPL ? "Wiadomości" : "Messages"
        case .settings: return L10n.isPL ? "Ustawienia" : "Settings"
        case .about: return L10n.isPL ? "O aplikacji" : "About"
        }
    }

    static var topItems: [NavigationItem] {
        [.home, .history, .send, .gallery, .messages, .settings]
    }

    static var bottomItems: [NavigationItem] {
        [.about]
    }
}
