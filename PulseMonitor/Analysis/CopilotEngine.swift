import Foundation

/// Natural-language performance copilot. Every statement is grounded in measured data.
public struct CopilotMessage: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public let role: Role
    public let text: String
    public let actions: [String]
    public let relatedCategory: String?

    public enum Role: String, Sendable, Codable {
        case assistant
        case system
    }

    public init(
        id: UUID = UUID(),
        role: Role = .assistant,
        text: String,
        actions: [String] = [],
        relatedCategory: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.actions = actions
        self.relatedCategory = relatedCategory
    }
}

public struct CopilotEngine: Sendable {
    public init() {}

    public func brief(
        metrics: SystemMetrics,
        processes: [ProcessInfoModel],
        findings: [BottleneckFinding],
        games: [ProcessInfoModel]
    ) -> [CopilotMessage] {
        var messages: [CopilotMessage] = []

        if let primary = findings.first {
            messages.append(.init(
                text: primary.detail.isEmpty ? primary.summary : "\(primary.summary) \(primary.detail)",
                actions: primary.recommendations,
                relatedCategory: primary.category.rawValue
            ))
        }

        if let leader = processes.max(by: { $0.cpuPercent < $1.cpuPercent }), leader.cpuPercent >= 25 {
            messages.append(.init(
                text: String(format: "%@ is using %.0f%% CPU right now.", leader.name, leader.cpuPercent),
                actions: ["Inspect \(leader.name) in Process Explorer", "Quit if you do not need it"],
                relatedCategory: "cpu"
            ))
        }

        if let hog = processes.max(by: { $0.memoryBytes < $1.memoryBytes }), hog.memoryBytes >= 2_000_000_000 {
            messages.append(.init(
                text: "\(hog.name) is using \(Formatters.bytes(hog.memoryBytes)) of RAM.",
                actions: ["Check for memory leaks if this grows without bound"],
                relatedCategory: "memory"
            ))
        }

        if let root = metrics.storage.volumes.first(where: \.isRoot), root.usedPercent > 90 {
            messages.append(.init(
                text: String(
                    format: "Your startup volume is %.0f%% full. Low free space slows swap and APFS performance.",
                    root.usedPercent
                ),
                actions: ["Empty Trash", "Review large files in Storage", "Move media off the internal drive"],
                relatedCategory: "storage"
            ))
        }

        if let health = metrics.battery.healthPercent, health < 85, metrics.battery.isPresent {
            messages.append(.init(
                text: String(format: "Battery health is %.0f%%. Expect shorter runtime than when the Mac was new.", health),
                actions: ["Review Battery module cycle count", "Avoid prolonged 100%% charge while hot if possible"],
                relatedCategory: "battery"
            ))
        }

        if !games.isEmpty {
            let game = games[0]
            if metrics.cpu.totalUsage > 85, let gpu = metrics.gpu.utilization, gpu < 50 {
                messages.append(.init(
                    text: "\(game.name) appears CPU limited — the CPU is busy while the GPU has headroom.",
                    actions: ["Lower simulation / render distance", "Close background apps", "Open Game Performance Lab"],
                    relatedCategory: "games"
                ))
            } else if let gpu = metrics.gpu.utilization, gpu > 90, metrics.cpu.totalUsage < 70 {
                messages.append(.init(
                    text: "\(game.name) looks GPU limited — the GPU is saturated while the CPU still has capacity.",
                    actions: ["Lower resolution or effects", "Cap frame rate", "Check thermal throttling"],
                    relatedCategory: "games"
                ))
            } else {
                messages.append(.init(
                    text: "Detected active game process: \(game.name).",
                    actions: ["Open Game Performance Lab for a session report"],
                    relatedCategory: "games"
                ))
            }
        }

        // WindowServer: we cannot read its GPU privately; only mention if the process is visible with high CPU.
        if let ws = processes.first(where: { $0.name == "WindowServer" }), ws.cpuPercent > 30 {
            messages.append(.init(
                text: String(
                    format: "WindowServer is using %.0f%% CPU, which often means heavy compositing, transparency, or external-display load.",
                    ws.cpuPercent
                ),
                actions: ["Reduce transparency in Accessibility settings", "Check Display Lab for refresh-rate changes"],
                relatedCategory: "display"
            ))
        }

        if messages.isEmpty {
            messages.append(.init(
                text: "No urgent issues in the latest sample. Health looks stable from the sensors we can read.",
                actions: ["Capture a snapshot for later comparison"]
            ))
        }

        return messages
    }
}
