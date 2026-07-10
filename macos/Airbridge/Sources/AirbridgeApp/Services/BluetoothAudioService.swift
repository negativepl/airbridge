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

    /// Whether the system default output device is currently playing audio
    /// ("running somewhere" — CoreAudio's transport-agnostic activity signal).
    private(set) var systemAudioActive = false
    var onAudioActivityChanged: ((Bool) -> Void)?

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
    /// AirPods-style automatic switching on playback start; off by default.
    var autoSwitchEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "headphoneAutoSwitch") }
        set { UserDefaults.standard.set(newValue, forKey: "headphoneAutoSwitch") }
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
        let name = selectedName
        let result: (connected: Bool, closed: Bool, audioActive: Bool)? = await Task.detached {
            guard let device = IOBluetoothDevice(addressString: address) else { return nil }
            // LE Audio (e.g. Galaxy Buds4 Pro) is invisible to IOBluetooth:
            // isConnected() only reflects the classic BR/EDR link, which may be
            // down even while audio is actively routed to the headset over LE
            // Audio. CoreAudio doesn't distinguish transports, so the presence
            // of an output device with the paired headphones' name is the
            // reliable source of truth for "audio is here" — treat either
            // signal as "connected".
            let classicConnected = device.isConnected()
            let coreAudioConnected = name.flatMap { Self.outputDeviceID(named: $0) } != nil
            let connected = classicConnected || coreAudioConnected
            let audioActive = Self.defaultOutputIsRunning()
            if connected && Date() < guardDeadline {
                // Headphones sneaked back during a handoff — release them again.
                // NOTE: closeConnection() only tears down the classic BR/EDR
                // link. If the route is actually LE Audio, this may not
                // release the phone's grip on it — known limitation, revisit
                // if the hardware pass shows the guard window failing.
                device.closeConnection()
                return (connected, true, audioActive)
            }
            return (connected, false, audioActive)
        }.value
        guard let result, !result.closed else { return }
        if result.connected != selectedConnected {
            selectedConnected = result.connected
            onStateChanged?(result.connected, address, selectedName ?? address)
        }
        if result.audioActive != systemAudioActive {
            systemAudioActive = result.audioActive
            onAudioActivityChanged?(result.audioActive)
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
    ///
    /// LE Audio gear (Galaxy Buds) may never bring the classic BR/EDR link up:
    /// openConnection() can then block for its full page timeout (30 s+) while
    /// the LE Audio route is already playing. So the classic connect is only a
    /// best-effort nudge fired in the background, and the authoritative success
    /// signal is the CoreAudio output device appearing — the same source of
    /// truth the state poll uses.
    func takeover() async -> Bool {
        guard let address = selectedAddress, let name = selectedName else { return false }
        guardUntil = .distantPast
        Task.detached {
            let device = IOBluetoothDevice(addressString: address)
            if device?.isConnected() != true {
                _ = device?.openConnection()
            }
        }
        // Wait for the audio route (up to 10 s), not for the classic link.
        for _ in 0..<20 {
            if let audioID = Self.outputDeviceID(named: name) {
                return Self.setDefaultOutput(audioID)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    // MARK: - CoreAudio

    nonisolated private static func outputDeviceID(named name: String) -> AudioDeviceID? {
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

    nonisolated private static func deviceName(_ id: AudioDeviceID) -> String? {
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

    nonisolated private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    /// Whether the CURRENT default output device is playing audio right now
    /// (`kAudioDevicePropertyDeviceIsRunningSomewhere`, global scope). Used to
    /// detect playback starting/stopping for the auto-switch engine —
    /// transport-agnostic, so it works for the built-in speakers as well as
    /// whatever Bluetooth output happens to be selected.
    nonisolated private static func defaultOutputIsRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr
        else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var isRunning: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &runningAddress, 0, nil, &runningSize, &isRunning) == noErr
        else { return false }
        return isRunning != 0
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
