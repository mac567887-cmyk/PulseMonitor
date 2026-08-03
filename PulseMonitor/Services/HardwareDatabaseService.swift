import AppKit
import Foundation
import IOKit
import IOKit.usb
import Metal

/// Enumerates identifiable hardware using public sysctl / IOKit / Metal / AppKit APIs.
/// Fields the OS does not publish stay nil — never fabricated.
public struct HardwareInventory: Sendable, Codable, Equatable {
    public var modelIdentifier: String?
    public var cpuBrand: String?
    public var cpuCoreCount: Int?
    public var gpuName: String?
    public var memoryBytes: UInt64?
    public var osVersion: String
    public var wifiInterface: String?
    public var bluetoothPresent: Bool
    public var pciDevices: [NamedDevice]
    public var usbDevices: [NamedDevice]
    public var storageDevices: [NamedDevice]
    public var displays: [NamedDevice]
    public var notes: [String]

    public struct NamedDevice: Sendable, Codable, Equatable, Identifiable {
        public var id: String
        public var name: String
        public var detail: String
        public var vendor: String?
    }
}

public actor HardwareDatabaseService {
    public init() {}

    public func inventory() async -> HardwareInventory {
        let model = Sysctl.string("hw.model")
        let cpuBrand = Sysctl.string("machdep.cpu.brand_string") ?? model
        let cores = Sysctl.integer("hw.ncpu", as: Int32.self).map(Int.init)
        let mem = Sysctl.integer("hw.memsize", as: UInt64.self)
        let gpu = MTLCreateSystemDefaultDevice()?.name
        let displays = await MainActor.run { Self.listDisplays() }

        return HardwareInventory(
            modelIdentifier: model,
            cpuBrand: cpuBrand,
            cpuCoreCount: cores,
            gpuName: gpu,
            memoryBytes: mem,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            wifiInterface: Self.firstMatchingName("IO80211Interface") ?? Self.firstMatchingName("Airport"),
            bluetoothPresent: Self.serviceExists("IOBluetoothHCIController"),
            pciDevices: Self.listServices(className: "IOPCIDevice", prefix: "pci", nameKeys: ["model", "IOName"], limit: 48),
            usbDevices: Self.listServices(
                className: kIOUSBDeviceClassName,
                prefix: "usb",
                nameKeys: ["USB Product Name", "kUSBProductString", "USB Vendor Name"],
                vendorKey: "USB Vendor Name",
                detailKeys: ["Device Speed"],
                limit: 64
            ),
            storageDevices: Self.listServices(
                className: "IOBlockStorageDevice",
                prefix: "storage",
                nameKeys: ["Product Name", "Device Characteristics"],
                vendorKey: "Vendor Name",
                limit: 24
            ),
            displays: displays,
            notes: [
                "Serial numbers and many firmware revisions are privacy-gated and omitted.",
                "Thunderbolt / Wi‑Fi chip marketing names are only shown when IOKit publishes them.",
                "Neural Engine utilization is not available through a public API."
            ]
        )
    }

    private static func listDisplays() -> [HardwareInventory.NamedDevice] {
        NSScreen.screens.enumerated().map { index, screen in
            let scale = screen.backingScaleFactor
            let pixelW = screen.frame.width * scale
            let pixelH = screen.frame.height * scale
            let hz = Int(screen.maximumFramesPerSecond)
            let detail = String(format: "%.0f×%.0f · %d Hz · %.0fx", pixelW, pixelH, hz, scale)
            return .init(id: "display-\(index)", name: screen.localizedName, detail: detail, vendor: nil)
        }
    }

    private static func listServices(
        className: String,
        prefix: String,
        nameKeys: [String],
        vendorKey: String? = nil,
        detailKeys: [String] = [],
        limit: Int
    ) -> [HardwareInventory.NamedDevice] {
        var result: [HardwareInventory.NamedDevice] = []
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        var index = 0
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            let name = nameKeys.compactMap { stringProperty(service, $0) }.first ?? "\(prefix) \(index)"
            let vendor = vendorKey.flatMap { stringProperty(service, $0) }
            let detail = detailKeys.compactMap { stringProperty(service, $0) }.first ?? className
            result.append(.init(id: "\(prefix)-\(index)", name: name, detail: detail, vendor: vendor))
            index += 1
            if index >= limit { break }
        }
        return result
    }

    private static func serviceExists(_ className: String) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        guard service != IO_OBJECT_NULL else { return false }
        IOObjectRelease(service)
        return true
    }

    private static func firstMatchingName(_ className: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        guard service != IO_OBJECT_NULL else { return nil }
        IOObjectRelease(service)
        return className
    }

    private static func stringProperty(_ service: io_registry_entry_t, _ key: String) -> String? {
        guard let raw = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        else { return nil }
        if let string = raw as? String, !string.isEmpty { return string }
        if let data = raw as? Data, let string = String(data: data, encoding: .utf8), !string.isEmpty { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }
}
