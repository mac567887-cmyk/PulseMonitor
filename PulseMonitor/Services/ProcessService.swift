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
        let architecture: String
        let codeSignature: String
    }

    /// How much of the process table this app can actually see.
    ///
    /// `proc_listallpids` returns every PID, but `proc_pidinfo` only answers for
    /// processes owned by the calling user. On a typical Mac that is well under
    /// half of them, so the shortfall is surfaced rather than quietly hidden.
    public struct Coverage: Sendable, Equatable {
        public let visible: Int
        public let total: Int
        public var isComplete: Bool { visible >= total }
    }

    public private(set) var coverage = Coverage(visible: 0, total: 0)

    public init() {}

    public func listProcesses() async -> [ProcessInfoModel] {
        let pids = Self.allPIDs()
        let now = Date()
        let dt = previousSampleDate.map { now.timeIntervalSince($0) } ?? 1.0
        var nextCPU: [Int32: Double] = [:]
        var results: [ProcessInfoModel] = []
        results.reserveCapacity(pids.count)

        // Built lazily. Reading `processIdentifier` forces AppKit to refetch each
        // application's dynamic properties over IPC, and it is only needed for
        // PIDs missing from the metadata cache — which on a settled system is
        // none of them.
        var runningApps: [Int32: NSRunningApplication]?
        func applicationsByPID() -> [Int32: NSRunningApplication] {
            if let runningApps { return runningApps }
            let map = Dictionary(
                uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app -> (Int32, NSRunningApplication)? in
                    guard app.processIdentifier > 0 else { return nil }
                    return (app.processIdentifier, app)
                }
            )
            runningApps = map
            return map
        }

        let coreCount = Double(ProcessInfo.processInfo.activeProcessorCount)
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
                let app = applicationsByPID()[pid]
                let bundleID = app?.bundleIdentifier
                meta = Metadata(
                    name: app?.localizedName ?? name,
                    path: path,
                    ppid: Self.parentPID(pid: pid),
                    bundleIdentifier: bundleID,
                    developer: bundleID?.split(separator: ".").prefix(2).joined(separator: ".").description,
                    isGame: GameDetector.isLikelyGame(name: name, path: path, bundleID: bundleID),
                    architecture: Self.architecture(pid: pid),
                    codeSignature: Self.codeSignature(pid: pid) ?? "—"
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
                    architecture: meta.architecture,
                    developer: meta.developer,
                    codeSignatureStatus: meta.codeSignature,
                    // No energy impact. Activity Monitor's figure blends CPU, GPU,
                    // wakeups and disk through a private coalition API; scaling CPU
                    // by a constant would only look like that number.
                    energyImpact: nil,
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
        coverage = Coverage(visible: results.count, total: pids.count)
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
        return String(nullTerminated: name)
    }

    private static func processPath(pid: Int32) -> String? {
        var path = [CChar](repeating: 0, count: Int(Libproc.PROC_PIDPATHINFO_MAXSIZE))
        let result = path.withUnsafeMutableBufferPointer { ptr in
            Libproc.pidPath(pid, ptr.baseAddress, UInt32(ptr.count))
        }
        guard result > 0 else { return nil }
        return String(nullTerminated: path)
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

    /// Per-process architecture from the kernel's own process record.
    ///
    /// The host architecture is not the answer: on Apple Silicon an Intel binary
    /// runs translated under Rosetta, and a 32-bit helper is neither. `P_LP64` and
    /// `P_TRANSLATED` in `kinfo_proc` describe the process that is actually
    /// running rather than the machine it runs on.
    private static func architecture(pid: Int32) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return "—" }

        let flags = info.kp_proc.p_flag
        let isTranslated = (flags & Int32(PM_P_TRANSLATED)) != 0
        let is64Bit = (flags & P_LP64) != 0

        if isTranslated { return "Intel (Rosetta)" }
        #if arch(arm64)
        return is64Bit ? "arm64" : "arm"
        #else
        return is64Bit ? "x86_64" : "i386"
        #endif
    }

    /// Code signing status straight from the kernel via `csops`.
    ///
    /// Reports what the kernel enforces, not whether a file happens to exist on
    /// disk. Returns nil for processes belonging to another user, where the call
    /// is not permitted.
    private static func codeSignature(pid: Int32) -> String? {
        var status: UInt32 = 0
        let result = withUnsafeMutablePointer(to: &status) { pointer in
            csops(pid, UInt32(PM_CS_OPS_STATUS), pointer, MemoryLayout<UInt32>.size)
        }
        guard result == 0 else { return nil }

        if status & UInt32(PM_CS_PLATFORM_BINARY) != 0 { return "Apple" }
        if status & UInt32(PM_CS_VALID) == 0 { return "Invalid" }
        if status & UInt32(PM_CS_HARD) != 0 { return "Hardened" }
        return "Valid"
    }
}
