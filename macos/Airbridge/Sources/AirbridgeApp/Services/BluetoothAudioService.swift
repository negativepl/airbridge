import Foundation
import IOBluetooth
import CoreAudio
import Observation

/// Mac side of the headphone handoff: connects/disconnects the user-selected
/// Bluetooth headphones (IOBluetooth) and, after a successful takeover, makes
/// them the system default audio output (CoreAudio) so sound actually moves.
@MainActor
@Observable
final class BluetoothAudioService {

    struct PairedAudioDevice: Identifiable, Equatable {
        let name: String
        let address: String
        var id: String { address }
    }

    /// Window after a release during which the headphones' auto-reconnect to
    /// this Mac is rejected, giving the phone time to grab them.
    private static let guardInterval: TimeInterval = 15

    private(set) var selectedConnected = false
    var onStateChanged: ((Bool, String, String) -> Void)?

    @ObservationIgnored private var guardUntil = Date.distantPast
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "headphoneHandoff") }
        set { UserDefaults.standard.set(newValue, forKey: "headphoneHandoff") }
    }
    var selectedAddress: String? {
        get { UserDefaults.standard.string(forKey: "headphoneAddress") }
        set { UserDefaults.standard.set(newValue, forKey: "headphoneAddress") }
    }
    var selectedName: String? {
        get { UserDefaults.standard.string(forKey: "headphoneName") }
        set { UserDefaults.standard.set(newValue, forKey: "headphoneName") }
    }

    static func pairedAudioDevices() -> [PairedAudioDevice] {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices
            .filter { $0.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio) }
            .compactMap { dev in
                guard let address = dev.addressString else { return nil }
                return PairedAudioDevice(name: dev.name ?? address, address: address)
            }
    }

    private func selectedDevice() -> IOBluetoothDevice? {
        guard let address = selectedAddress else { return nil }
        return IOBluetoothDevice(addressString: address)
    }

    // MARK: - State monitoring

    /// IOBluetooth connect notifications are selector-based and global; a
    /// 2 s poll of isConnected() on the one selected device is simpler, cheap,
    /// and cannot leak observers. Also enforces the post-release guard.
    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.pollOnce()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func pollOnce() {
        guard enabled, let device = selectedDevice(),
              let address = selectedAddress else { return }
        let connected = device.isConnected()
        if connected && Date() < guardUntil {
            // Headphones sneaked back during a handoff — release them again.
            device.closeConnection()
            return
        }
        if connected != selectedConnected {
            selectedConnected = connected
            onStateChanged?(connected, address, selectedName ?? address)
        }
    }

    // MARK: - Handoff operations

    /// Disconnect the headphones so the phone can take them.
    func release() async -> Bool {
        guard let device = selectedDevice(), let address = selectedAddress else { return false }
        guardUntil = Date().addingTimeInterval(Self.guardInterval)
        if !device.isConnected() { return true }
        // IOBluetoothDevice isn't Sendable; re-resolve it by address inside the
        // detached task instead of capturing the main-actor-isolated instance.
        let status = await Task.detached {
            IOBluetoothDevice(addressString: address)?.closeConnection() ?? kIOReturnError
        }.value
        return status == kIOReturnSuccess
    }

    /// Connect the headphones to this Mac and route audio to them.
    func takeover() async -> Bool {
        guard let device = selectedDevice(), let address = selectedAddress,
              let name = selectedName else { return false }
        guardUntil = .distantPast
        if !device.isConnected() {
            let status = await Task.detached {
                IOBluetoothDevice(addressString: address)?.openConnection() ?? kIOReturnError
            }.value
            guard status == kIOReturnSuccess else { return false }
        }
        // The CoreAudio device appears a moment after the BT link is up.
        for _ in 0..<20 {
            if let audioID = Self.outputDeviceID(named: name) {
                return Self.setDefaultOutput(audioID)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    // MARK: - CoreAudio

    private static func outputDeviceID(named name: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return nil }
        for id in ids where deviceName(id) == name && hasOutputStreams(id) {
            return id
        }
        return nil
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let err = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        return err == noErr ? (name as String) : nil
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = id
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID) == noErr
    }
}
