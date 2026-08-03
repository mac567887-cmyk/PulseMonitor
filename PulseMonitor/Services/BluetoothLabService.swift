import CoreBluetooth
import Foundation
import Observation

/// Bluetooth lab using CoreBluetooth. Host-controller chip details beyond
/// CBCentralManager state are limited without private APIs.
@MainActor
@Observable
public final class BluetoothLabService: NSObject, CBCentralManagerDelegate {
    public private(set) var stateDescription: String = "Unknown"
    public private(set) var isScanning = false
    public private(set) var peripherals: [PeripheralRow] = []
    public private(set) var notes: [String] = [
        "macOS does not publish per-device codec, audio quality or controller latency through public APIs.",
        "Battery levels appear only when a peripheral exposes the standard Battery Service and allows reads.",
        "PulseMonitor never invents RSSI or battery values."
    ]

    public struct PeripheralRow: Identifiable, Equatable {
        public var id: UUID
        public var name: String
        public var rssi: Int?
        public var connectable: Bool
    }

    private var central: CBCentralManager?
    private var seen: [UUID: PeripheralRow] = [:]

    public func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
        updateState()
    }

    public func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    public func startScan() {
        guard let central, central.state == .poweredOn else {
            stateDescription = "Bluetooth unavailable or unauthorized."
            return
        }
        seen.removeAll()
        peripherals = []
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
    }

    private func updateState() {
        guard let central else {
            stateDescription = "Not started"
            return
        }
        switch central.state {
        case .poweredOn: stateDescription = "Powered On"
        case .poweredOff: stateDescription = "Powered Off"
        case .unauthorized: stateDescription = "Unauthorized — enable Bluetooth access for PulseMonitor."
        case .unsupported: stateDescription = "Unsupported on this Mac."
        case .resetting: stateDescription = "Resetting"
        case .unknown: stateDescription = "Unknown"
        @unknown default: stateDescription = "Unknown"
        }
    }

    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            self.apply(state: state)
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        let localName = peripheral.name
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? false
        let rssiValue = RSSI.intValue
        Task { @MainActor in
            let name = localName ?? advertised ?? "Unknown device"
            let row = PeripheralRow(
                id: id,
                name: name,
                rssi: rssiValue == 127 ? nil : rssiValue,
                connectable: connectable
            )
            self.seen[id] = row
            self.peripherals = self.seen.values.sorted { ($0.rssi ?? -999) > ($1.rssi ?? -999) }
        }
    }

    private func apply(state: CBManagerState) {
        switch state {
        case .poweredOn: stateDescription = "Powered On"
        case .poweredOff: stateDescription = "Powered Off"
        case .unauthorized: stateDescription = "Unauthorized — enable Bluetooth access for PulseMonitor."
        case .unsupported: stateDescription = "Unsupported on this Mac."
        case .resetting: stateDescription = "Resetting"
        case .unknown: stateDescription = "Unknown"
        @unknown default: stateDescription = "Unknown"
        }
        if state != .poweredOn { isScanning = false }
    }
}
