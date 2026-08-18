import Foundation

/// Machine-wide resource usage at a point in time.
public struct ResourceSnapshot: Equatable, Sendable, Codable {
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let memoryFreeFraction: Double
    public let diskFreeBytes: UInt64
    public let diskTotalBytes: UInt64

    public init(
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        memoryFreeFraction: Double,
        diskFreeBytes: UInt64,
        diskTotalBytes: UInt64
    ) {
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.memoryFreeFraction = memoryFreeFraction
        self.diskFreeBytes = diskFreeBytes
        self.diskTotalBytes = diskTotalBytes
    }

    /// Fraction of swap in use, or `nil` when the system has no swap allocated.
    ///
    /// A freshly booted Mac reports a total of zero. That is the healthiest
    /// state there is, so it must not divide by zero and must not be mistaken
    /// for pressure.
    public var swapUsedFraction: Double? {
        guard swapTotalBytes > 0 else { return nil }
        return Double(swapUsedBytes) / Double(swapTotalBytes)
    }

    /// Fraction of the disk still free, or `nil` when capacity is unknown.
    public var diskFreeFraction: Double? {
        guard diskTotalBytes > 0 else { return nil }
        return Double(diskFreeBytes) / Double(diskTotalBytes)
    }
}
