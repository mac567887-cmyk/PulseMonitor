import Foundation
import Observation

public struct ToolchainRecord: Sendable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let path: String?
    public let version: String?
    public let manager: String
}

@MainActor
@Observable
public final class PackageManagerService {
    public private(set) var tools: [ToolchainRecord] = []
    public private(set) var isScanning = false

    public init() {}

    public func scan() async {
        isScanning = true
        defer { isScanning = false }

        let probes: [(name: String, manager: String, path: String, args: [String])] = [
            ("Homebrew", "Homebrew", "/opt/homebrew/bin/brew", ["--version"]),
            ("Homebrew (Intel)", "Homebrew", "/usr/local/bin/brew", ["--version"]),
            ("MacPorts", "MacPorts", "/opt/local/bin/port", ["version"]),
            ("Python 3", "Python", "/usr/bin/python3", ["--version"]),
            ("Node", "Node", "/usr/local/bin/node", ["--version"]),
            ("Node (Homebrew)", "Node", "/opt/homebrew/bin/node", ["--version"]),
            ("Java", "Java", "/usr/bin/java", ["-version"]),
            ("Rustc", "Rust", "/opt/homebrew/bin/rustc", ["--version"]),
            ("Cargo", "Rust", "/opt/homebrew/bin/cargo", ["--version"]),
            ("Go", "Go", "/opt/homebrew/bin/go", ["version"]),
            ("Swift", "Swift", "/usr/bin/swift", ["--version"]),
            ("Xcode CLT", "Swift", "/usr/bin/xcode-select", ["-p"])
        ]

        var found: [ToolchainRecord] = []
        for probe in probes {
            guard FileManager.default.isExecutableFile(atPath: probe.path) else { continue }
            let version = await Self.runVersion(path: probe.path, args: probe.args)
            found.append(.init(name: probe.name, path: probe.path, version: version, manager: probe.manager))
        }
        tools = found
    }

    private static func runVersion(path: String, args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: .newlines).first
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
