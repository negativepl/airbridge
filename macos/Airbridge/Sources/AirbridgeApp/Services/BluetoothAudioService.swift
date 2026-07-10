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

    struct PairedAudioDevice: Identifiable, Equatable, Sendable {
        let name: String
        let address: String
        var id: String { address }
    }

    /// IOBluetooth reports "5c-d3-3d-1e-3f-d1"; Android reports "5C:D3:3D:1E:3F:D1".
    /// The wire and stored format is the Android one; IOBluetoothDevice(addressString:)
    /// accepts both, so canonicalizing here is safe.
    nonisolated static func canonicalAddress(_ raw: String) -> String {
        raw.replacingOccurrences(of: "-", with: ":").uppercased()
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
        get { UserDefaults.standard.string(forKey: "headphoneAddress").map(Self.canonicalAddress) }
        set { UserDefaults.standard.set(newValue, forKey: "headphoneAddress") }
    }
    var selectedName: String? {
        get { UserDefaults.standard.string(forKey: "headphoneName") }
        set { UserDefaults.standard.set(newValue, forKey: "headphoneName") }
    }

    /// IOBluetooth enumeration is blocking IPC; run it off the main actor so the
    /// Settings UI doesn't stall while it re-runs on section re-render.
    static func pairedAudioDevices() async -> [PairedAudioDevice] {
        await Task.detached {
            let devices = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
            var seen = Set<String>()
            var result: [PairedAudioDevice] = []
            for dev in devices {
                guard dev.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio),
                      let rawAddress = dev.addressString else { continue }
                let address = canonicalAddress(rawAddress)
                guard seen.insert(address).inserted else { continue }
                result.append(PairedAudioDevice(name: dev.name ?? address, address: address))
            }
            return result
        }.value
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
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    deinit {
        monitorTask?.cancel()
    }

    private func pollOnce() async {
        guard enabled, let address = selectedAddress else { return }
        // IOBluetoothDevice isn't Sendable and both isConnected() and
        // closeConnection() are blocking IOBluetooth IPC calls; resolve the
        // device and perform them off the main actor, capturing only the
        // Sendable address string and a snapshot of the guard deadline.
        let guardDeadline = guardUntil
        let result: (connected: Bool, closed: Bool)? = await Task.detached {
            guard let device = IOBluetoothDevice(addressString: address) else { return nil }
            let connected = device.isConnected()
            if connected && Date() < guardDeadline {
                // Headphones sneaked back during a handoff — release them again.
                device.closeConnection()
                return (connected, true)
            }
            return (connected, false)
        }.value
        guard let result, !result.closed else { return }
        if result.connected != selectedConnected {
            selectedConnected = result.connected
            onStateChanged?(result.connected, address, selectedName ?? address)
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
        guard let address = selectedAddress, let name = selectedName else { return false }
        guardUntil = .distantPast
        let isConnected = await Task.detached {
            IOBluetoothDevice(addressString: address)?.isConnected() ?? false
        }.value
        if !isConnected {
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
