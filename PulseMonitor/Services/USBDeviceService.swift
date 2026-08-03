import Foundation
import IOKit
import IOKit.usb
import Observation

public struct USBDeviceRecord: Sendable, Identifiable, Equatable {
    public var id: String
    public let name: String
    public let vendor: String?
    public let speed: String?
    public let locationID: String?
    public let canEject: Bool
    public let bsdName: String?
}

@MainActor
@Observable
public final class USBDeviceService {
    public private(set) var devices: [USBDeviceRecord] = []
    public private(set) var lastError: String?

    public init() {}

    public func refresh() {
        var result: [USBDeviceRecord] = []
        var iterator = io_iterator_t()
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            lastError = "Unable to query USB registry."
            devices = []
            return
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        var index = 0
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            let name = stringProperty(service, "USB Product Name")
                ?? stringProperty(service, "kUSBProductString")
                ?? "USB Device \(index)"
            let vendor = stringProperty(service, "USB Vendor Name")
            let speed = stringProperty(service, "Device Speed")
            let location = stringProperty(service, "locationID") ?? stringProperty(service, "LocationID")
            let bsd = stringProperty(service, "BSD Name")
            result.append(
                USBDeviceRecord(
                    id: location ?? "usb-\(index)",
                    name: name,
                    vendor: vendor,
                    speed: speed,
                    locationID: location,
                    canEject: bsd != nil,
                    bsdName: bsd
                )
            )
            index += 1
            if index > 100 { break }
        }
        devices = result
        lastError = nil
    }

    /// Attempts a safe unmount for mass-storage devices that publish a BSD name.
    public func eject(_ device: USBDeviceRecord) -> String? {
        guard let bsd = device.bsdName else {
            return "This device does not publish a BSD name, so PulseMonitor cannot eject it safely."
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", bsd]
        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                refresh()
                return nil
            }
            let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "eject failed"
            return err.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return error.localizedDescription
        }
    }

    private func stringProperty(_ service: io_registry_entry_t, _ key: String) -> String? {
        guard let raw = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        else { return nil }
        if let string = raw as? String, !string.isEmpty { return string }
        if let data = raw as? Data, let string = String(data: data, encoding: .utf8), !string.isEmpty { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }
}
