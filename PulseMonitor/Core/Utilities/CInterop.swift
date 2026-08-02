import Foundation

public extension String {
    /// Decodes a fixed-size C character buffer, stopping at the first NUL.
    ///
    /// The BSD and libproc calls used throughout the services fill an
    /// over-allocated buffer and leave the tail zeroed, so the buffer's `count`
    /// is not the string's length.
    init(nullTerminated buffer: [CChar]) {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self = String(decoding: bytes, as: UTF8.self)
    }
}

/// Typed reads of the BSD `sysctl` namespace.
public enum Sysctl {
    /// Reads a string-valued key, sizing the buffer from the kernel's own
    /// reported length. Returns `nil` when the key is absent on this hardware.
    public static func string(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(nullTerminated: buffer)
        return value.isEmpty ? nil : value
    }

    /// Reads a fixed-width integer key.
    public static func integer<T: FixedWidthInteger>(_ key: String, as type: T.Type = T.self) -> T? {
        var value = T.zero
        var size = MemoryLayout<T>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
