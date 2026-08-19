import Foundation

/// The kernel's own verdict on memory pressure.
///
/// Read from `kern.memorystatus_vm_pressure_level`. These are the same levels
/// `dispatch` exposes as `DISPATCH_MEMORYPRESSURE_NORMAL` / `WARN` / `CRITICAL`,
/// the ones that drive Activity Monitor's pressure graph and decide when macOS
/// starts terminating applications.
///
/// Using it means one fewer threshold to invent. The kernel weighs compression
/// ratio, clean page availability, file-backed pressure and recent system
/// behaviour — none of which is visible from here. Asking it is both cheaper
/// and more correct than approximating it from a paging rate.
public enum MemoryPressureLevel: Int, Sendable, Codable, Comparable {
    /// The sysctl was unavailable or returned something unrecognized.
    ///
    /// Treated as the absence of evidence rather than as evidence of calm: it
    /// never escalates a finding, it only fails to escalate one.
    case unknown = 0
    case normal = 1
    case warning = 2
    case critical = 4

    public static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
