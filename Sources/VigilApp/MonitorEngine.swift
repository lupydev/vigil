import Foundation
import VigilCore
import VigilSystem
import Observation

/// Drives the sample → store → diagnose → notify loop.
///
/// Advise-only by construction: the engine holds no port capable of changing
/// the machine, so no future edit can accidentally make it act. Granting it
/// that power later has to be a deliberate architectural change, which is
/// precisely the intent.
@MainActor
@Observable
public final class MonitorEngine {
    public private(set) var anomalies: [Anomaly] = []
    public private(set) var lastCheck: Date?
    public private(set) var lastError: String?
    public private(set) var sampleCount: Int = 0
    public private(set) var retainedBytes: Int = 0

    private let processSampler: any ProcessSampler
    private let resourceSampler: any ResourceSampler
    private let store: any SampleStore
    private let notifier: UserNotificationNotifier
    private let diagnostician: Diagnostician
    private let clock: any Clock
    private let interval: TimeInterval
    private let window: TimeInterval

    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        processSampler: any ProcessSampler = LibprocProcessSampler(),
        resourceSampler: any ResourceSampler = SysctlResourceSampler(),
        store: any SampleStore = InMemorySampleStore(),
        notifier: UserNotificationNotifier = UserNotificationNotifier(),
        diagnostician: Diagnostician = .standard,
        clock: any Clock = SystemClock(),
        interval: TimeInterval = 60,
        window: TimeInterval = 3_600
    ) {
        self.processSampler = processSampler
        self.resourceSampler = resourceSampler
        self.store = store
        self.notifier = notifier
        self.diagnostician = diagnostician
        self.clock = clock
        self.interval = interval
        self.window = window
    }

    public var notificationsAvailable: Bool { notifier.isAvailable }

    public var worstSeverity: Severity? {
        anomalies.map(\.severity).max()
    }

    public func start() {
        guard task == nil else { return }

        // A rule whose threshold sits below the compactor's floor could never
        // fire — its evidence is discarded before it is stored. Surface that as
        // an error rather than as findings that mysteriously never appear.
        let blindSpots = (store as? InMemorySampleStore)?
            .blindSpots(against: diagnostician.rules) ?? []
        if !blindSpots.isEmpty {
            lastError = blindSpots.joined(separator: "; ")
        }

        task = Task { [weak self] in
            guard let self else { return }
            await self.notifier.requestAuthorization()

            while !Task.isCancelled {
                await self.checkNow()
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func checkNow() async {
        do {
            let sample = Sample(
                timestamp: clock.now,
                processes: try processSampler.sampleProcesses(),
                resources: try resourceSampler.sampleResources()
            )
            // The store keeps only plausible candidates; sampling still reads
            // every process, because the CPU delta needs the whole picture.
            try store.append(sample)

            let history = try store.history(within: window)
            let found = diagnostician.diagnose(history)

            anomalies = found
            sampleCount = history.samples.count
            retainedBytes = (store as? InMemorySampleStore)?.approximateBytes ?? 0
            lastCheck = sample.timestamp
            lastError = nil

            await notifier.notify(found)
        } catch {
            lastError = String(describing: error)
        }
    }
}
