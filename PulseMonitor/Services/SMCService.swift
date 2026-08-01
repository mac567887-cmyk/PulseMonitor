import Foundation
import IOKit

/// Direct reader for Apple's System Management Controller.
///
/// The SMC is the only source for real fan RPM and on-die temperature sensors on
/// Intel Macs. Apple Silicon machines do not expose these keys, so callers must
/// consult `CapabilityService` before presenting anything from here.
///
/// Layouts mirror `AppleSMC`'s user-client structures. They are fixed by the
/// kernel extension's ABI and must not be reordered.
public actor SMCService {
    // MARK: - Kernel ABI

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private enum Selector: UInt32 {
        case kSMCHandleYPCEvent = 2
        case kSMCReadKey = 5
        case kSMCWriteKey = 6
        case kSMCGetKeyInfo = 9
    }

    // MARK: - Connection

    private var connection: io_connect_t = 0
    private var didAttemptOpen = false
    private var keyInfoCache: [UInt32: SMCKeyInfoData] = [:]

    public init() {}

    /// Opens the AppleSMC user client. Returns false when the service is absent,
    /// which is the expected outcome on Apple Silicon.
    private func open() -> Bool {
        if connection != 0 { return true }
        if didAttemptOpen { return false }
        didAttemptOpen = true

        guard let matching = IOServiceMatching("AppleSMC") else { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            return false
        }
        connection = conn
        return true
    }

    public func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    // MARK: - Public reads

    /// Number of fans reported by the SMC, or nil when unavailable.
    public func fanCount() -> Int? {
        guard let value = readUInt8(key: "FNum") else { return nil }
        return Int(value)
    }

    /// Live fan readings. Empty when the SMC is unavailable.
    public func fans() -> [FanReading] {
        guard let count = fanCount(), count > 0, count < 10 else { return [] }
        return (0..<count).compactMap { index in
            guard let actual = readFloat(key: "F\(index)Ac") else { return nil }
            return FanReading(
                index: index,
                currentRPM: Double(actual),
                minimumRPM: readFloat(key: "F\(index)Mn").map(Double.init),
                maximumRPM: readFloat(key: "F\(index)Mx").map(Double.init),
                targetRPM: readFloat(key: "F\(index)Tg").map(Double.init)
            )
        }
    }

    /// Named temperature sensors that responded on this machine.
    ///
    /// Keys that the SMC does not implement are skipped rather than reported as
    /// zero, so an absent sensor never looks like a cold one.
    public func temperatures() -> [TemperatureReading] {
        let sensors: [(String, String)] = [
            ("TC0P", "CPU Proximity"),
            ("TC0D", "CPU Die"),
            ("TC0E", "CPU PECI"),
            ("TCXC", "CPU Core"),
            ("TG0P", "GPU Proximity"),
            ("TG0D", "GPU Die"),
            ("TM0P", "Memory Proximity"),
            ("TA0P", "Ambient"),
            ("TB0T", "Battery"),
            ("Ts0P", "Palm Rest"),
            ("TW0P", "Airport"),
            ("TH0A", "Drive Bay")
        ]

        return sensors.compactMap { key, label in
            guard let celsius = readFloat(key: key) else { return nil }
            // The SMC returns implausible values for unpopulated sensors.
            guard celsius > 1, celsius < 130 else { return nil }
            return TemperatureReading(key: key, label: label, celsius: Double(celsius))
        }
    }

    /// CPU and GPU package power in watts where the SMC publishes them.
    public func powerReadings() -> [PowerReading] {
        let sensors: [(String, String)] = [
            ("PCPC", "CPU Package"),
            ("PCPG", "GPU Package"),
            ("PSTR", "System Total"),
            ("PDTR", "DC In")
        ]
        return sensors.compactMap { key, label in
            guard let watts = readFloat(key: key), watts > 0, watts < 400 else { return nil }
            return PowerReading(key: key, label: label, watts: Double(watts))
        }
    }

    public struct FanReading: Sendable, Identifiable, Equatable {
        public var id: Int { index }
        public let index: Int
        public let currentRPM: Double
        public let minimumRPM: Double?
        public let maximumRPM: Double?
        public let targetRPM: Double?

        /// Fraction of the fan's usable range currently in use.
        public var loadFraction: Double? {
            guard let minimumRPM, let maximumRPM, maximumRPM > minimumRPM else { return nil }
            return min(1, max(0, (currentRPM - minimumRPM) / (maximumRPM - minimumRPM)))
        }
    }

    public struct TemperatureReading: Sendable, Identifiable, Equatable {
        public var id: String { key }
        public let key: String
        public let label: String
        public let celsius: Double
    }

    public struct PowerReading: Sendable, Identifiable, Equatable {
        public var id: String { key }
        public let key: String
        public let label: String
        public let watts: Double
    }

    // MARK: - Typed reads

    private func readUInt8(key: String) -> UInt8? {
        guard let (info, bytes) = read(key: key), info.dataSize >= 1 else { return nil }
        return bytes[0]
    }

    /// Decodes the SMC's several numeric encodings into a float.
    private func readFloat(key: String) -> Float? {
        guard let (info, bytes) = read(key: key) else { return nil }

        switch fourCharString(info.dataType) {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Float(bitPattern: raw)

        case "fpe2":
            // Unsigned fixed point, 14 integer bits and 2 fractional bits.
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Float(raw >> 2)

        case "fp88":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Float(raw) / 256

        case "sp78":
            // Signed fixed point, 7 integer bits and 8 fractional bits.
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Float(raw) / 256

        case "ui8 ", "ui8":
            guard bytes.count >= 1 else { return nil }
            return Float(bytes[0])

        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Float(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))

        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return Float(raw)

        default:
            return nil
        }
    }

    // MARK: - Raw transport

    private func read(key: String) -> (SMCKeyInfoData, [UInt8])? {
        guard open() else { return nil }
        let code = fourCharCode(key)

        guard let info = keyInfo(for: code) else { return nil }

        var input = SMCParamStruct()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = UInt8(Selector.kSMCReadKey.rawValue)

        guard let output = call(input), output.result == 0 else { return nil }

        let size = Int(min(info.dataSize, 32))
        var bytes = [UInt8](repeating: 0, count: size)
        withUnsafeBytes(of: output.bytes) { raw in
            for index in 0..<size { bytes[index] = raw[index] }
        }
        return (info, bytes)
    }

    private func keyInfo(for code: UInt32) -> SMCKeyInfoData? {
        if let cached = keyInfoCache[code] { return cached }

        var input = SMCParamStruct()
        input.key = code
        input.data8 = UInt8(Selector.kSMCGetKeyInfo.rawValue)

        guard let output = call(input), output.result == 0, output.keyInfo.dataSize > 0 else {
            return nil
        }
        keyInfoCache[code] = output.keyInfo
        return output.keyInfo
    }

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        var inputCopy = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let status = IOConnectCallStructMethod(
            connection,
            Selector.kSMCHandleYPCEvent.rawValue,
            &inputCopy,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        return status == kIOReturnSuccess ? output : nil
    }

    private func fourCharCode(_ key: String) -> UInt32 {
        var code: UInt32 = 0
        for character in key.utf8.prefix(4) {
            code = code << 8 | UInt32(character)
        }
        return code
    }

    private func fourCharString(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}
