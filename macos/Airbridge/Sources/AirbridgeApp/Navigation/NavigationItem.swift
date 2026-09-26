import Foundation

enum NavigationItem: String, CaseIterable, Identifiable, Hashable {
    case home
    case send
    case gallery
    case files
    case messages
    case mirror
    case settings

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .send: return "paperplane.fill"
        case .gallery: return "photo.on.rectangle"
        case .files: return "folder.fill"
        case .messages: return "message.fill"
        case .mirror: return "iphone.gen3.radiowaves.left.and.right"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return L10n.isPL ? "Główna" : "Home"
        case .send: return L10n.isPL ? "Wyślij" : "Send"
        case .gallery: return L10n.isPL ? "Galeria" : "Gallery"
        case .files: return L10n.isPL ? "Pliki" : "Files"
        case .messages: return L10n.isPL ? "Wiadomości" : "Messages"
        case .mirror: return L10n.isPL ? "Udostępnianie ekranu" : "Screen Sharing"
        case .settings: return L10n.isPL ? "Ustawienia" : "Settings"
        }
    }

    static var topItems: [NavigationItem] {
        [.home, .send, .gallery, .files, .messages, .mirror, .settings]
    }
}
