import Foundation

/// Rich process record for the Process Explorer.
public struct ProcessInfoModel: Sendable, Codable, Identifiable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let ppid: Int32
    public let name: String
    public let bundleIdentifier: String?
    public let executablePath: String?
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let threadCount: Int
    public let architecture: String
    public let developer: String?
    public let codeSignatureStatus: String
    public let energyImpact: Double?
    public let diskBytesPerSec: Double?
    public let networkBytesPerSec: Double?
    public let gpuPercent: Double?
    public let isGame: Bool
    public let user: String?

    public var memoryMegabytes: Double {
        Double(memoryBytes) / 1_048_576.0
    }
}
