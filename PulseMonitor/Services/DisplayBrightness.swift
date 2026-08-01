import Foundation
import IOKit
import LibprocBridge

/// Reads and writes panel brightness through IOKit's display parameter interface.
///
/// Only displays that publish a writable `brightness` parameter respond here,
/// which in practice means Intel built-in panels. Every entry point returns nil
/// or false rather than guessing when the parameter is absent.
public enum DisplayBrightness {
    private static var parameter: CFString { "brightness" as CFString }

    public static func currentBrightness() -> Float? {
        var value: Float = 0
        var found = false
        forEachDisplayService { service in
            guard !found else { return }
            if IODisplayGetFloatParameter(service, 0, parameter, &value) == kIOReturnSuccess {
                found = true
            }
        }
        return found ? value : nil
    }

    @discardableResult
    public static func setBrightness(_ value: Float) -> Bool {
        var success = false
        forEachDisplayService { service in
            if IODisplaySetFloatParameter(service, 0, parameter, value) == kIOReturnSuccess {
                success = true
            }
        }
        return success
    }

    private static func forEachDisplayService(_ body: (io_service_t) -> Void) {
        guard let matching = IOServiceMatching("IODisplayConnect") else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}
