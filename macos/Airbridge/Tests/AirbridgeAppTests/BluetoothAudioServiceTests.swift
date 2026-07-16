import XCTest
import Observation
@testable import AirbridgeApp

/// Ustawienia słuchawek muszą być obserwowalne przez SwiftUI: zapis z poziomu
/// UI ma natychmiast unieważnić widok. Właściwości liczone wprost na
/// UserDefaults nie zostawiają śladu dla @Observable — te testy pilnują, żeby
/// każda z nich przechodziła przez śledzony stan.
@MainActor
final class BluetoothAudioServiceTests: XCTestCase {

    private static let suiteName = "BluetoothAudioServiceTests"

    private final class Flag: @unchecked Sendable {
        var fired = false
    }

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        return defaults
    }

    private func assertObservable(
        _ mutate: (BluetoothAudioService) -> Void,
        access: (BluetoothAudioService) -> Void,
        _ label: String
    ) {
        let service = BluetoothAudioService(defaults: freshDefaults())
        let flag = Flag()
        withObservationTracking {
            access(service)
        } onChange: {
            flag.fired = true
        }
        mutate(service)
        XCTAssertTrue(flag.fired, "\(label): zmiana nie została zaobserwowana — UI się nie odświeży")
    }

    func testEnabledIsObservable() {
        assertObservable({ $0.enabled = true }, access: { _ = $0.enabled }, "enabled")
    }

    func testSelectedAddressIsObservable() {
        assertObservable(
            { $0.selectedAddress = "5C:D3:3D:1E:3F:D1" },
            access: { _ = $0.selectedAddress }, "selectedAddress")
    }

    func testSelectedNameIsObservable() {
        assertObservable(
            { $0.selectedName = "Buds4 Pro" },
            access: { _ = $0.selectedName }, "selectedName")
    }

    func testAutoSwitchEnabledIsObservable() {
        assertObservable(
            { $0.autoSwitchEnabled = true },
            access: { _ = $0.autoSwitchEnabled }, "autoSwitchEnabled")
    }

    /// Ustawienia muszą nadal trafiać do UserDefaults i wracać po restarcie,
    /// a adres z zapisu w formacie IOBluetooth ma wracać skanonizowany.
    func testSettingsPersistAcrossInstances() {
        let defaults = freshDefaults()
        let service = BluetoothAudioService(defaults: defaults)
        service.enabled = true
        service.selectedAddress = "5c-d3-3d-1e-3f-d1"
        service.selectedName = "Buds4 Pro"
        service.autoSwitchEnabled = true

        let reloaded = BluetoothAudioService(defaults: defaults)
        XCTAssertTrue(reloaded.enabled)
        XCTAssertEqual(reloaded.selectedAddress, "5C:D3:3D:1E:3F:D1")
        XCTAssertEqual(reloaded.selectedName, "Buds4 Pro")
        XCTAssertTrue(reloaded.autoSwitchEnabled)
    }
}
