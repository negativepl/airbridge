import Foundation

// MARK: - Localization

/// Simple locale-aware string provider for Polish and English.
enum L10n {
    static var locale: String { Locale.current.language.languageCode?.identifier ?? "en" }
    static var isPL: Bool { locale == "pl" }

    static var connected: String { isPL ? "Połączono" : "Connected" }
    static var notConnected: String { isPL ? "Brak połączenia" : "Not connected" }
    static var connectedTo: String { isPL ? "Połączono z" : "Connected to" }
    static var searching: String { isPL ? "Szukam urządzeń..." : "Searching for devices..." }
    static var sendFile: String { isPL ? "Wyślij plik..." : "Send File..." }
    static var pairDevice: String { isPL ? "Sparuj urządzenie" : "Pair Device" }
    static var disconnect: String { isPL ? "Rozłącz" : "Disconnect" }
    static var settings: String { isPL ? "Ustawienia..." : "Settings..." }
    static var quit: String { isPL ? "Zakończ Airbridge" : "Quit Airbridge" }
    static var lastSynced: String { isPL ? "Ostatnio zsynchronizowano:" : "Last synced:" }
    static var clipboardSynced: String { isPL ? "Schowek zsynchronizowany" : "Clipboard synced" }
    static var pairTitle: String { isPL ? "Sparuj z Androidem" : "Pair with Android" }
    static var pairDesc: String { isPL ? "Otwórz Airbridge na telefonie i zeskanuj ten kod QR" : "Open Airbridge on your phone and scan this QR code" }
    static var close: String { isPL ? "Zamknij" : "Close" }
    static var launchAtLogin: String { isPL ? "Uruchom przy logowaniu" : "Launch at login" }
    static var showNotifications: String { isPL ? "Pokaż powiadomienia" : "Show notifications" }
    static var downloadFolder: String { isPL ? "Folder pobierania:" : "Download folder:" }
    static var change: String { isPL ? "Zmień..." : "Change..." }
    static var pairedWith: String { isPL ? "Sparowano z:" : "Paired with:" }
    static var noDevicePaired: String { isPL ? "Brak sparowanego urządzenia" : "No device paired" }
    static var dropFilesHere: String { isPL ? "Upuść pliki tutaj lub kliknij aby wybrać" : "Drop files here or click to select" }
    static var sendToAndroid: String { isPL ? "Wyślij do Androida" : "Send to Android" }
    static var fileReceived: String { isPL ? "Otrzymano plik:" : "File received:" }
    static var reconnect: String { isPL ? "Połącz ponownie" : "Reconnect" }
    static var fileTransfer: String { isPL ? "Transfer plików" : "File Transfer" }
    static var connection: String { isPL ? "Połączenie" : "Connection" }
    static var general: String { isPL ? "Ogólne" : "General" }
    static var status: String { isPL ? "Status" : "Status" }
    static var pairedDevice: String { isPL ? "Sparowane urządzenie" : "Paired Device" }
    static var localIP: String { isPL ? "Lokalny IP" : "Local IP" }
    static var receivedFilesSaved: String { isPL ? "Otrzymane pliki będą zapisane w tym folderze" : "Received files will be saved to this folder" }
    static var device: String { isPL ? "Urządzenie" : "Device" }
    static var selectFiles: String { isPL ? "Wybierz pliki..." : "Select files..." }
    static var sending: String { isPL ? "Wysyłanie..." : "Sending..." }
    static var pairingFailed: String { isPL ? "Nie udało się wygenerować kodu parowania" : "Failed to generate pairing payload" }
    static var qrFailed: String { isPL ? "Generowanie QR nie powiodło się" : "QR generation failed" }
    static var settingsTitle: String { isPL ? "Ustawienia Airbridge" : "Airbridge Settings" }
    static var sendFiles: String { isPL ? "Wyślij pliki" : "Send Files" }
    static var openAirbridge: String { isPL ? "Otwórz Airbridge" : "Open Airbridge" }
    static var connectedToDevice: String { isPL ? "Połączono z" : "Connected to" }
}
