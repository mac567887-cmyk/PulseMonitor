import Foundation

/// Shared formatting helpers for bytes, rates, temperatures, and percentages.
public enum Formatters {
    public static func bytes(_ value: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(clamping: value))
    }

    public static func bytesPerSecond(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue < 1024 { return String(format: "%.0f B/s", value) }
        if absValue < 1024 * 1024 { return String(format: "%.1f KB/s", value / 1024) }
        if absValue < 1024 * 1024 * 1024 { return String(format: "%.1f MB/s", value / (1024 * 1024)) }
        return String(format: "%.2f GB/s", value / (1024 * 1024 * 1024))
    }

    public static func percent(_ value: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", value)
    }

    public static func celsius(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f°C", value)
    }

    public static func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f W", value)
    }

    public static func mhz(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 1000 {
            return String(format: "%.2f GHz", value / 1000)
        }
        return String(format: "%.0f MHz", value)
    }

    public static func uptime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func rpm(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f RPM", value)
    }
}
