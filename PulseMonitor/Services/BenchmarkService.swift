import Foundation
import Metal

/// Result of one benchmark run.
public struct BenchmarkResult: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let kind: BenchmarkKind
    public let score: Double
    public let unit: String
    public let detail: String
    public let date: Date

    public init(id: UUID = UUID(), kind: BenchmarkKind, score: Double, unit: String, detail: String, date: Date = .now) {
        self.id = id
        self.kind = kind
        self.score = score
        self.unit = unit
        self.detail = detail
        self.date = date
    }
}

public enum BenchmarkKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case cpuSingleCore
    case cpuMultiCore
    case memoryBandwidth
    case diskWrite
    case diskRead
    case gpuCompute

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cpuSingleCore: "CPU Single-Core"
        case .cpuMultiCore: "CPU Multi-Core"
        case .memoryBandwidth: "Memory Bandwidth"
        case .diskWrite: "Disk Write"
        case .diskRead: "Disk Read"
        case .gpuCompute: "GPU Compute"
        }
    }

    public var symbol: String {
        switch self {
        case .cpuSingleCore, .cpuMultiCore: "cpu"
        case .memoryBandwidth: "memorychip"
        case .diskWrite, .diskRead: "internaldrive"
        case .gpuCompute: "cube"
        }
    }
}

/// Runs real workloads and measures throughput.
///
/// Every number here comes from timing actual work: integer and floating point
/// kernels for CPU, large buffer copies for memory, file I/O against a temporary
/// file for disk, and a Metal compute dispatch for GPU. Nothing is synthesised.
public actor BenchmarkService {
    private let historyURL: URL
    private var history: [BenchmarkResult]

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = support.appendingPathComponent("PulseMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.historyURL = directory.appendingPathComponent("benchmarks.json")

        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([BenchmarkResult].self, from: data) {
            self.history = decoded
        } else {
            self.history = []
        }
    }

    public func storedResults() -> [BenchmarkResult] {
        history.sorted { $0.date > $1.date }
    }

    public func results(for kind: BenchmarkKind) -> [BenchmarkResult] {
        history.filter { $0.kind == kind }.sorted { $0.date < $1.date }
    }

    /// Most recent previous score for the same benchmark, for delta display.
    public func previousScore(for kind: BenchmarkKind, excluding id: UUID) -> Double? {
        history
            .filter { $0.kind == kind && $0.id != id }
            .max { $0.date < $1.date }?
            .score
    }

    public func run(_ kind: BenchmarkKind) async -> BenchmarkResult {
        let result: BenchmarkResult = switch kind {
        case .cpuSingleCore: runCPUSingleCore()
        case .cpuMultiCore: runCPUMultiCore()
        case .memoryBandwidth: runMemoryBandwidth()
        case .diskWrite: runDiskWrite()
        case .diskRead: runDiskRead()
        case .gpuCompute: runGPUCompute()
        }
        record(result)
        return result
    }

    private func record(_ result: BenchmarkResult) {
        history.append(result)
        // Keep the file small; a hundred runs per kind is far more than anyone reviews.
        if history.count > 600 {
            history.removeFirst(history.count - 600)
        }
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    public func clearHistory() {
        history.removeAll()
        try? FileManager.default.removeItem(at: historyURL)
    }

    // MARK: - CPU

    /// Mixed integer and floating point kernel, scored as iterations per second
    /// normalised so a 2019 mobile i7 core lands near 1000.
    private nonisolated func runCPUSingleCore() -> BenchmarkResult {
        let start = Date()
        let iterations = Self.cpuKernel(rounds: 2_400)
        let elapsed = Date().timeIntervalSince(start)
        let opsPerSecond = Double(iterations) / max(elapsed, 0.0001)
        let score = opsPerSecond / 1_000_000

        return BenchmarkResult(
            kind: .cpuSingleCore,
            score: score,
            unit: "pts",
            detail: String(format: "%.2f s on one core", elapsed)
        )
    }

    private nonisolated func runCPUMultiCore() -> BenchmarkResult {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let start = Date()

        // DispatchQueue.concurrentPerform saturates every available core and
        // blocks until all of them finish, which is exactly the shape we want.
        let counter = Counter()
        DispatchQueue.concurrentPerform(iterations: cores) { _ in
            let result = Self.cpuKernel(rounds: 2_400)
            counter.add(result)
        }

        let elapsed = Date().timeIntervalSince(start)
        let opsPerSecond = Double(counter.value) / max(elapsed, 0.0001)
        let score = opsPerSecond / 1_000_000

        return BenchmarkResult(
            kind: .cpuMultiCore,
            score: score,
            unit: "pts",
            detail: String(format: "%.2f s across %d cores", elapsed, cores)
        )
    }

    /// Deliberately resistant to constant folding: the result feeds the return
    /// value so the optimiser cannot elide the loop.
    private nonisolated static func cpuKernel(rounds: Int) -> Int {
        var accumulator: UInt64 = 0x9E3779B97F4A7C15
        var float = 1.000001
        var operations = 0

        for _ in 0..<rounds {
            for step in 0..<1_000 {
                accumulator ^= accumulator << 13
                accumulator ^= accumulator >> 7
                accumulator ^= accumulator << 17
                accumulator = accumulator &+ UInt64(step)
                float = (float * 1.0000003).squareRoot() + 1.0
                operations += 1
            }
        }

        // Fold both accumulators in so neither loop can be optimised away.
        return operations &+ Int(accumulator & 0x1) &+ (float > 0 ? 0 : 1)
    }

    /// Minimal thread-safe counter for the concurrent CPU run.
    private final class Counter: @unchecked Sendable {
        private var storage = 0
        private let lock = NSLock()

        func add(_ amount: Int) {
            lock.lock()
            storage += amount
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    // MARK: - Memory

    /// Copies a buffer large enough to defeat last-level cache and reports the
    /// sustained bandwidth in gigabytes per second.
    private nonisolated func runMemoryBandwidth() -> BenchmarkResult {
        let elementCount = 32 * 1024 * 1024 / MemoryLayout<UInt64>.size
        var source = [UInt64](repeating: 0xA5A5A5A5A5A5A5A5, count: elementCount)
        var destination = [UInt64](repeating: 0, count: elementCount)
        let passes = 8

        let start = Date()
        for pass in 0..<passes {
            source.withUnsafeMutableBufferPointer { src in
                destination.withUnsafeMutableBufferPointer { dst in
                    dst.baseAddress?.update(from: src.baseAddress!, count: elementCount)
                    // Touch one element per pass so the copy cannot be hoisted.
                    src[pass] = dst[pass] &+ 1
                }
            }
        }
        let elapsed = Date().timeIntervalSince(start)

        let bytesMoved = Double(elementCount * MemoryLayout<UInt64>.size * passes * 2)
        let gigabytesPerSecond = bytesMoved / max(elapsed, 0.0001) / 1_000_000_000

        return BenchmarkResult(
            kind: .memoryBandwidth,
            score: gigabytesPerSecond,
            unit: "GB/s",
            detail: String(format: "%.0f MB copied in %.2f s", bytesMoved / 1_000_000, elapsed)
        )
    }

    // MARK: - Disk

    private nonisolated var scratchURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pulsemonitor-benchmark.bin")
    }

    private nonisolated func runDiskWrite() -> BenchmarkResult {
        let chunkSize = 8 * 1024 * 1024
        let chunks = 32
        let payload = Data(repeating: 0x5A, count: chunkSize)
        let url = scratchURL

        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return BenchmarkResult(
                kind: .diskWrite, score: 0, unit: "MB/s",
                detail: "Could not open a scratch file in the temporary directory."
            )
        }

        let start = Date()
        for _ in 0..<chunks {
            try? handle.write(contentsOf: payload)
        }
        // fsync so the timing reflects the device, not just the page cache.
        fsync(handle.fileDescriptor)
        let elapsed = Date().timeIntervalSince(start)
        try? handle.close()

        let megabytes = Double(chunkSize * chunks) / 1_048_576
        return BenchmarkResult(
            kind: .diskWrite,
            score: megabytes / max(elapsed, 0.0001),
            unit: "MB/s",
            detail: String(format: "%.0f MB written and flushed in %.2f s", megabytes, elapsed)
        )
    }

    private nonisolated func runDiskRead() -> BenchmarkResult {
        let url = scratchURL
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return BenchmarkResult(
                kind: .diskRead, score: 0, unit: "MB/s",
                detail: "Run the write benchmark first so there is a file to read."
            )
        }

        // Purge this file from the unified buffer cache so the read hits storage.
        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)

        let start = Date()
        var total = 0
        while let chunk = try? handle.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty {
            total += chunk.count
        }
        let elapsed = Date().timeIntervalSince(start)
        try? handle.close()

        let megabytes = Double(total) / 1_048_576
        return BenchmarkResult(
            kind: .diskRead,
            score: megabytes / max(elapsed, 0.0001),
            unit: "MB/s",
            detail: String(format: "%.0f MB read uncached in %.2f s", megabytes, elapsed)
        )
    }

    public func removeScratchFile() {
        try? FileManager.default.removeItem(at: scratchURL)
    }

    // MARK: - GPU

    /// Dispatches a compute kernel and measures achieved throughput in GFLOP/s.
    private nonisolated func runGPUCompute() -> BenchmarkResult {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return BenchmarkResult(
                kind: .gpuCompute, score: 0, unit: "GFLOP/s",
                detail: "No Metal device is available on this machine."
            )
        }
        guard let queue = device.makeCommandQueue() else {
            return BenchmarkResult(
                kind: .gpuCompute, score: 0, unit: "GFLOP/s",
                detail: "Metal refused to create a command queue."
            )
        }

        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void saxpy_loop(device float *out [[buffer(0)]],
                               constant uint &rounds [[buffer(1)]],
                               uint gid [[thread_position_in_grid]]) {
            float acc = (float)gid * 0.000001f;
            float coefficient = 1.0000001f;
            for (uint i = 0; i < rounds; ++i) {
                acc = fma(acc, coefficient, 0.0000001f);
            }
            out[gid] = acc;
        }
        """

        let library: MTLLibrary
        let pipeline: MTLComputePipelineState
        do {
            library = try device.makeLibrary(source: source, options: nil)
            guard let function = library.makeFunction(name: "saxpy_loop") else {
                throw NSError(domain: "PulseMonitor", code: 1)
            }
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            return BenchmarkResult(
                kind: .gpuCompute, score: 0, unit: "GFLOP/s",
                detail: "Metal shader compilation failed: \(error.localizedDescription)"
            )
        }

        let threadCount = 1 << 20
        let rounds: UInt32 = 512
        guard let buffer = device.makeBuffer(
            length: threadCount * MemoryLayout<Float>.size, options: .storageModePrivate
        ) else {
            return BenchmarkResult(
                kind: .gpuCompute, score: 0, unit: "GFLOP/s",
                detail: "Could not allocate a GPU buffer."
            )
        }

        var roundsValue = rounds
        let start = Date()
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return BenchmarkResult(
                kind: .gpuCompute, score: 0, unit: "GFLOP/s",
                detail: "Could not encode the compute pass."
            )
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.setBytes(&roundsValue, length: MemoryLayout<UInt32>.size, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: threadCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(pipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1
            )
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let elapsed = Date().timeIntervalSince(start)

        // Each fused multiply-add counts as two floating point operations.
        let flops = Double(threadCount) * Double(rounds) * 2
        return BenchmarkResult(
            kind: .gpuCompute,
            score: flops / max(elapsed, 0.0001) / 1_000_000_000,
            unit: "GFLOP/s",
            detail: "\(device.name) — \(String(format: "%.3f s", elapsed))"
        )
    }
}
