import Darwin
import Foundation
import VigilCore

/// Reads machine-wide resource usage through `sysctl`, Mach and the filesystem.
public struct SysctlResourceSampler: ResourceSampler {
    private let volumeURL: URL

    public init(volumeURL: URL = URL(fileURLWithPath: "/System/Volumes/Data")) {
        self.volumeURL = volumeURL
    }

    public func sampleResources() throws -> ResourceSnapshot {
        let swap = try Self.swapUsage()
        let disk = Self.diskUsage(at: volumeURL)

        return ResourceSnapshot(
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            memoryFreeFraction: Self.memoryFreeFraction(),
            memoryPressureLevel: Self.memoryPressureLevel(),
            diskFreeBytes: disk.free,
            diskTotalBytes: disk.total
        )
    }

    private static func swapUsage() throws -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { throw SamplerError.resourcesUnavailable }
        return (usage.xsu_used, usage.xsu_total)
    }

    /// Free plus inactive pages as a fraction of physical memory.
    ///
    /// Inactive pages count as available: macOS reclaims them on demand, so
    /// treating them as used would make a healthy machine look starved.
    private static func memoryFreeFraction() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        // `vm_kernel_page_size` is a mutable C global and therefore not
        // Sendable under strict concurrency; `sysconf` returns the same value.
        let pageSize = Double(sysconf(_SC_PAGESIZE))
        let available = (Double(stats.free_count) + Double(stats.inactive_count)) * pageSize
        let physical = Double(ProcessInfo.processInfo.physicalMemory)
        guard physical > 0 else { return 0 }

        return min(1, available / physical)
    }

    /// The kernel's live memory pressure verdict.
    ///
    /// Same levels `dispatch` publishes as `DISPATCH_MEMORYPRESSURE_NORMAL`
    /// (1), `WARN` (2) and `CRITICAL` (4). An unavailable sysctl yields
    /// `.unknown`, which never escalates a finding.
    private static func memoryPressureLevel() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard result == 0 else { return .unknown }
        return MemoryPressureLevel(rawValue: Int(level)) ?? .unknown
    }

    private static func diskUsage(at url: URL) -> (free: UInt64, total: UInt64) {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, 0) }

        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        return (free, total)
    }
}
