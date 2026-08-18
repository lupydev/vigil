import VigilCore
import SwiftUI

/// Carries the measured height of the anomaly list up to its container.
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MenuContentView: View {
    let engine: MonitorEngine
    @State private var expanded: Set<String> = []
    @State private var listHeight: CGFloat = 0

    /// Ceiling before the list starts scrolling instead of growing.
    private let maximumListHeight: CGFloat = 380

    /// Used until the first measurement arrives, so the list is never invisible.
    private let provisionalListHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if engine.anomalies.isEmpty {
                emptyState
            } else {
                // A ScrollView has no intrinsic height. Given only `maxHeight`
                // it is free to collapse to nothing, which showed a header
                // reading "1 anomaly" above an empty gap. So the content is
                // measured and the frame is set to that, clamped — which also
                // keeps the panel growing correctly as rows expand.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(engine.anomalies) { anomaly in
                            AnomalyRow(
                                anomaly: anomaly,
                                isExpanded: expanded.contains(anomaly.id),
                                toggle: { toggle(anomaly.id) }
                            )
                            Divider()
                        }
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                }
                .frame(height: resolvedListHeight)
                .onPreferenceChange(ContentHeightKey.self) { height in
                    listHeight = height
                }
            }

            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text(headerLabel)
                .font(.headline)
            Spacer()
            Button("Check now") {
                Task { await engine.checkNow() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Everything looks healthy.")
                .font(.callout)
            Text("Still collecting history — thresholds get more accurate as samples accumulate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(lastCheckLabel)
                Spacer()
                Text("\(engine.sampleCount) samples\(storageLabel)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error = engine.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if !engine.notificationsAvailable {
                Text("Notifications need a bundled .app — run the packaging script.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Advise-only. This app never acts on your machine.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(12)
    }

    private var headerLabel: String {
        switch engine.anomalies.count {
        case 0: "No anomalies"
        case 1: "1 anomaly"
        case let count: "\(count) anomalies"
        }
    }

    private var resolvedListHeight: CGFloat {
        guard listHeight > 0 else { return provisionalListHeight }
        return min(listHeight, maximumListHeight)
    }

    private var storageLabel: String {
        " · \(engine.retainedBytes.formatted(.byteCount(style: .memory))) in memory"
    }

    private var lastCheckLabel: String {
        guard let lastCheck = engine.lastCheck else { return "Not checked yet" }
        return "Checked \(lastCheck.formatted(date: .omitted, time: .standard))"
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }
}

struct AnomalyRow: View {
    let anomaly: Anomaly
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)

                    Text(anomaly.title)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(anomaly.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(anomaly.evidence, id: \.self) { line in
                        Text("• \(line)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(anomaly.remedy.summary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)

                if let command = anomaly.remedy.command {
                    HStack(spacing: 6) {
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))

                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                }
            }
        }
        .padding(12)
    }

    private var color: Color {
        switch anomaly.severity {
        case .critical: .red
        case .warning: .orange
        case .info: .secondary
        }
    }
}
