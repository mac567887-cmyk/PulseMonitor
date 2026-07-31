import Foundation
import AppKit
import Darwin
import LibprocBridge

/// Enumerates running processes using libproc / BSD APIs.
public actor ProcessService {
    /// Previous CPU time samples keyed by PID for differential usage.
    private var previousCPUTime: [Int32: Double] = [:]
    private var previousSampleDate: Date?

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

        for pid in pids {
            guard let name = Self.processName(pid: pid) else { continue }
            let path = Self.processPath(pid: pid)
            let totalCPUTime = Self.totalCPUTimeSeconds(pid: pid)
            nextCPU[pid] = totalCPUTime

            let cpuPercent: Double
            if let prev = previousCPUTime[pid], dt > 0 {
                cpuPercent = min(100 * coreCount, max(0, ((totalCPUTime - prev) / dt) * 100.0))
            } else {
                cpuPercent = 0
            }

            let memory = Self.residentMemory(pid: pid)
            let threads = Self.threadCount(pid: pid)
            let ppid = Self.parentPID(pid: pid)
            let arch = Self.architecture()
            let app = runningApps[pid]
            let developer = app?.bundleIdentifier?.split(separator: ".").prefix(2).joined(separator: ".")
            let isGame = GameDetector.isLikelyGame(name: name, path: path, bundleID: app?.bundleIdentifier)

            results.append(
                ProcessInfoModel(
                    pid: pid,
                    ppid: ppid,
                    name: app?.localizedName ?? name,
                    bundleIdentifier: app?.bundleIdentifier,
                    executablePath: path,
                    cpuPercent: cpuPercent,
                    memoryBytes: memory,
                    threadCount: threads,
                    architecture: arch,
                    developer: developer.map { String($0) },
                    codeSignatureStatus: path == nil ? "Unknown" : "Present",
                    energyImpact: cpuPercent * 1.2,
                    diskBytesPerSec: nil,
                    networkBytesPerSec: nil,
                    gpuPercent: nil,
                    isGame: isGame,
                    user: nil
                )
            )
        }

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

    private static func residentMemory(pid: Int32) -> UInt64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            Libproc.pidInfo(pid, PROC_PIDTASKINFO, 0, $0, size)
        }
        guard result == size else { return 0 }
        return UInt64(info.pti_resident_size)
    }

    private static func threadCount(pid: Int32) -> Int {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            Libproc.pidInfo(pid, PROC_PIDTASKINFO, 0, $0, size)
        }
        guard result == size else { return 0 }
        return Int(info.pti_threadnum)
    }

    private static func totalCPUTimeSeconds(pid: Int32) -> Double {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            Libproc.pidInfo(pid, PROC_PIDTASKINFO, 0, $0, size)
        }
        guard result == size else { return 0 }
        return Double(info.pti_total_user + info.pti_total_system) / 1_000_000_000.0
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
