import Foundation
import AppKit
import Darwin
import LibprocBridge

/// Enumerates running processes using libproc / BSD APIs.
public actor ProcessService {
    /// Previous CPU time samples keyed by PID for differential usage.
    private var previousCPUTime: [Int32: Double] = [:]
    private var previousSampleDate: Date?
    private var metadataCache: [Int32: Metadata] = [:]

    /// Per-process values that cannot change over a PID's lifetime, so they are read
    /// once instead of on every sampling tick.
    private struct Metadata {
        let name: String
        let path: String?
        let ppid: Int32
        let bundleIdentifier: String?
        let developer: String?
        let isGame: Bool
    }

    public init() {}

    public func listProcesses() async -> [ProcessInfoModel] {
        let pids = Self.allPIDs()
        let now = Date()
        let dt = previousSampleDate.map { now.timeIntervalSince($0) } ?? 1.0
        var nextCPU: [Int32: Double] = [:]
        var results: [ProcessInfoModel] = []
        results.reserveCapacity(pids.count)

        let runningApps = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app -> (Int32, NSRunningApplication)? in
                guard app.processIdentifier > 0 else { return nil }
                return (app.processIdentifier, app)
            }
        )

        let coreCount = Double(ProcessInfo.processInfo.activeProcessorCount)
        let arch = Self.architecture()
        var liveMetadata: [Int32: Metadata] = [:]
        liveMetadata.reserveCapacity(pids.count)

        for pid in pids {
            guard let task = Self.taskInfo(pid: pid) else { continue }

            let meta: Metadata
            if let cached = metadataCache[pid] {
                meta = cached
            } else {
                guard let name = Self.processName(pid: pid) else { continue }
                let path = Self.processPath(pid: pid)
                let app = runningApps[pid]
                let bundleID = app?.bundleIdentifier
                meta = Metadata(
                    name: app?.localizedName ?? name,
                    path: path,
                    ppid: Self.parentPID(pid: pid),
                    bundleIdentifier: bundleID,
                    developer: bundleID?.split(separator: ".").prefix(2).joined(separator: ".").description,
                    isGame: GameDetector.isLikelyGame(name: name, path: path, bundleID: bundleID)
                )
            }
            liveMetadata[pid] = meta

            let totalCPUTime = Double(task.pti_total_user + task.pti_total_system) / 1_000_000_000.0
            nextCPU[pid] = totalCPUTime

            let cpuPercent: Double
            if let prev = previousCPUTime[pid], dt > 0 {
                cpuPercent = min(100 * coreCount, max(0, ((totalCPUTime - prev) / dt) * 100.0))
            } else {
                cpuPercent = 0
            }

            results.append(
                ProcessInfoModel(
                    pid: pid,
                    ppid: meta.ppid,
                    name: meta.name,
                    bundleIdentifier: meta.bundleIdentifier,
                    executablePath: meta.path,
                    cpuPercent: cpuPercent,
                    memoryBytes: UInt64(task.pti_resident_size),
                    threadCount: Int(task.pti_threadnum),
                    architecture: arch,
                    developer: meta.developer,
                    codeSignatureStatus: meta.path == nil ? "Unknown" : "Present",
                    energyImpact: cpuPercent * 1.2,
                    diskBytesPerSec: nil,
                    networkBytesPerSec: nil,
                    gpuPercent: nil,
                    isGame: meta.isGame,
                    user: nil
                )
            )
        }

        // Replacing the cache wholesale drops entries for exited PIDs.
        metadataCache = liveMetadata
        previousCPUTime = nextCPU
        previousSampleDate = now
        return results.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    public func kill(pid: Int32, force: Bool = false) async -> Bool {
        Darwin.kill(pid, force ? SIGKILL : SIGTERM) == 0
    }

    nonisolated public func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private static func allPIDs() -> [Int32] {
        let numberOrBytes = Libproc.listAllPIDs(nil, 0)
        guard numberOrBytes > 0 else { return [] }
        // proc_listallpids returns count of pids when buffersize queried with size hint in bytes on some SDKs;
        // allocate generously.
        let capacity = max(Int(numberOrBytes), 512)
        var buffer = [pid_t](repeating: 0, count: capacity)
        let filled = buffer.withUnsafeMutableBufferPointer { ptr in
            Libproc.listAllPIDs(ptr.baseAddress, Int32(ptr.count * MemoryLayout<pid_t>.stride))
        }
        guard filled > 0 else { return [] }
        let count = min(Int(filled), buffer.count)
        return Array(buffer.prefix(count)).map { Int32($0) }.filter { $0 > 0 }
    }

    private static func processName(pid: Int32) -> String? {
        var name = [CChar](repeating: 0, count: 1024)
        let result = name.withUnsafeMutableBufferPointer { ptr in
            Libproc.name(pid, ptr.baseAddress, UInt32(ptr.count))
        }
        guard result > 0 else { return nil }
        return String(cString: name)
    }

    private static func processPath(pid: Int32) -> String? {
        var path = [CChar](repeating: 0, count: Int(Libproc.PROC_PIDPATHINFO_MAXSIZE))
        let result = path.withUnsafeMutableBufferPointer { ptr in
            Libproc.pidPath(pid, ptr.baseAddress, UInt32(ptr.count))
        }
        guard result > 0 else { return nil }
        return String(cString: path)
    }

    /// Single task-info read per process; CPU time, resident size, and thread count
    /// all come from this one syscall.
    private static func taskInfo(pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            Libproc.pidInfo(pid, PROC_PIDTASKINFO, 0, $0, size)
        }
        guard result == size else { return nil }
        return info
    }

    private static func parentPID(pid: Int32) -> Int32 {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            Libproc.pidInfo(pid, PROC_PIDT_SHORTBSDINFO, 0, $0, size)
        }
        guard result == size else { return 0 }
        return Int32(info.pbsi_ppid)
    }

    private static func architecture() -> String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
