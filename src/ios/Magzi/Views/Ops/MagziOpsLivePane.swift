import SwiftUI

/// Buffered live frames from `MagziCockpitSocket.shared.frames` (newest first, capped).
@MainActor
final class MagziOpsLiveFeed: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let frame: MagziCockpitFrame
        let received = Date()

        var isError: Bool {
            switch frame {
            case .event(let e): return e.status == "error"
            case .audit(let a): return a.isError
            case .unknown: return false
            }
        }
    }

    static let capacity = 500

    @Published private(set) var items: [Item] = []
    @Published private(set) var buffered: [Item] = []
    @Published var isPaused = false {
        didSet { if !isPaused && oldValue { flush() } }
    }
    @Published var errorsOnly = false

    /// Outlives socket sessions: a reconnect replays the backfill, so dedupe by seq here too.
    private var lastSeq: Int64 = -1

    func receive(_ frame: MagziCockpitFrame) {
        if case .event(let e) = frame, let s = e.seq {
            guard s > lastSeq else { return }
            lastSeq = s
        }
        let item = Item(frame: frame)
        if isPaused {
            buffered.insert(item, at: 0)
            if buffered.count > Self.capacity { buffered.removeLast(buffered.count - Self.capacity) }
        } else {
            items.insert(item, at: 0)
            if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
        }
    }

    func clear() {
        items = []
        buffered = []
    }

    func reset() {
        clear()
        lastSeq = -1
        isPaused = false
        errorsOnly = false
    }

    private func flush() {
        guard !buffered.isEmpty else { return }
        items.insert(contentsOf: buffered, at: 0)
        buffered = []
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
    }

    var visible: [Item] { errorsOnly ? items.filter(\.isError) : items }
}

/// Live: streaming bus/audit feed + `/api/watch` history with filters.
struct MagziOpsLivePane: View {
    @ObservedObject var store: MagziOpsStore
    @ObservedObject var feed: MagziOpsLiveFeed
    @ObservedObject private var socket = MagziCockpitSocket.shared

    @State private var mode: Mode = .live
    @State private var filterSession = ""
    @State private var filterRun = ""
    @State private var filterScope = ""
    @State private var historyErrorsOnly = false
    @State private var history: [MagziAuditFrame]?
    @State private var historyError: String?
    @State private var historyLoading = false

    enum Mode: String, CaseIterable, Identifiable {
        case live = "Live"
        case history = "History"
        var id: String { rawValue }
    }

    var body: some View {
        MagziOpsPane(refresh: refresh) {
            Picker("Feed", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _ in MagziOpsHaptics.selection() }

            switch mode {
            case .live: liveContent
            case .history: historyContent
            }
        }
        .onAppear { MagziCockpitSocket.shared.connect() }
        .onDisappear { MagziCockpitSocket.shared.disconnect() }
        .onReceive(MagziCockpitSocket.shared.frames) { feed.receive($0) }
    }

    private func refresh() async {
        switch mode {
        case .live:
            MagziCockpitSocket.shared.disconnect()
            MagziCockpitSocket.shared.connect()
        case .history:
            await loadHistory()
        }
    }

    // MARK: Live

    @ViewBuilder
    private var liveContent: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            HStack(spacing: MagziDesign.Spacing.s) {
                MagziStatusDot(socket.isConnected ? .live : .attention)
                Text(socket.isConnected ? "Live" : "Reconnecting…")
                    .font(MagziDesign.Typography.headline)
                    .foregroundStyle(MagziDesign.label)
                Spacer()
                Button {
                    MagziOpsHaptics.selection()
                    feed.isPaused.toggle()
                } label: {
                    Label(feed.isPaused ? "Resume" : "Pause", systemImage: feed.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(MagziCompactButtonStyle(tint: feed.isPaused ? MagziDesign.mint : MagziDesign.labelSecondary))
            }
            if !socket.isConnected, let error = socket.lastError {
                Text(error)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .lineLimit(2)
            }
            HStack {
                Toggle("Errors only", isOn: $feed.errorsOnly)
                    .font(MagziDesign.Typography.subheadline)
                    .tint(MagziDesign.rose)
            }
            HStack {
                Text("\(feed.items.count) frames\(feed.isPaused && !feed.buffered.isEmpty ? " · \(feed.buffered.count) waiting" : "")")
                    .font(MagziDesign.Typography.caption)
                    .foregroundStyle(MagziDesign.labelTertiary)
                    .monospacedDigit()
                Spacer()
                if !feed.items.isEmpty {
                    Button("Clear") { feed.clear() }
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.mint)
                }
            }
        }
        .magziCard()

        let visible = feed.visible
        if visible.isEmpty {
            MagziEmptyState(
                systemImage: "dot.radiowaves.left.and.right",
                title: feed.errorsOnly ? "No errors" : "Waiting for activity",
                message: socket.isConnected
                    ? "Pipeline events and audit frames stream in here as Magzi works."
                    : "Connecting to the cockpit stream…"
            )
            .magziCard()
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { MagziOpsDivider() }
                    MagziOpsFrameRow(frame: item.frame)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .magziCard(padding: MagziDesign.Spacing.m)
            .animation(MagziDesign.Motion.standard, value: visible.first?.id)
        }
    }

    // MARK: History

    @ViewBuilder
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            filterField("Session", text: $filterSession, placeholder: "whatsapp:+44…")
            filterField("Run", text: $filterRun, placeholder: "run id")
            filterField("Scope", text: $filterScope, placeholder: "e.g. turn, tool, scheduler")
            Toggle("Errors only", isOn: $historyErrorsOnly)
                .font(MagziDesign.Typography.subheadline)
                .tint(MagziDesign.rose)
            Button {
                Task { await loadHistory() }
            } label: {
                if historyLoading { ProgressView() } else { Text("Load history") }
            }
            .buttonStyle(MagziPrimaryButtonStyle())
            .disabled(historyLoading)
        }
        .magziCard()

        if let historyError {
            MagziOpsErrorCard(message: historyError, retry: loadHistory)
        }
        if let history {
            if history.isEmpty {
                MagziEmptyState(systemImage: "line.3.horizontal.decrease.circle", title: "Nothing matched", message: "Try a broader filter.")
                    .magziCard()
            } else {
                MagziSectionHeader("\(history.count) events")
                VStack(spacing: 0) {
                    ForEach(Array(history.reversed().enumerated()), id: \.offset) { index, frame in
                        if index > 0 { MagziOpsDivider() }
                        MagziOpsFrameRow(frame: .audit(frame))
                    }
                }
                .magziCard(padding: MagziDesign.Spacing.m)
            }
        } else if historyLoading {
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    MagziOpsFrameRow(frame: .audit(MagziAuditFrame(time: "00:00:00", scope: "scope", action: "action", status: "ok", summary: "Placeholder summary text")))
                }
            }
            .magziCard(padding: MagziDesign.Spacing.m)
            .redacted(reason: .placeholder)
        }
    }

    private func filterField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: MagziDesign.Spacing.m) {
            Text(label)
                .font(MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.labelSecondary)
                .frame(width: 64, alignment: .leading)
            TextField(placeholder, text: text)
                .font(MagziDesign.Typography.mono)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, MagziDesign.Spacing.m)
                .frame(minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous)
                        .fill(MagziDesign.surfaceSecondary)
                )
        }
    }

    private func loadHistory() async {
        historyLoading = true
        defer { historyLoading = false }
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        do {
            history = try await store.api.watch(
                session: clean(filterSession), run: clean(filterRun), scope: clean(filterScope),
                errorsOnly: historyErrorsOnly, limit: 200
            )
            historyError = nil
        } catch {
            if let text = store.message(for: error) { historyError = text }
        }
    }
}

/// Compact mono row for one live/audit frame.
struct MagziOpsFrameRow: View {
    let frame: MagziCockpitFrame

    var body: some View {
        switch frame {
        case .event(let e):
            row(
                time: MagziOpsFormat.clock(ms: e.at),
                status: e.status,
                title: [e.kind, e.layer, e.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                detail: e.text ?? e.data.map(MagziOpsFormat.compact),
                tag: e.session,
                live: e.isLive
            )
        case .audit(let a):
            row(
                time: MagziOpsFormat.clock(a.time),
                status: a.status,
                title: [a.scope, a.action].compactMap { $0 }.joined(separator: " · "),
                detail: a.summary,
                tag: a.session,
                live: false
            )
        case .unknown(let json):
            row(time: "--:--:--", status: nil, title: "frame", detail: MagziOpsFormat.compact(json), tag: nil, live: false)
        }
    }

    private func row(time: String, status: String?, title: String, detail: String?, tag: String?, live: Bool) -> some View {
        HStack(alignment: .top, spacing: MagziDesign.Spacing.s) {
            MagziStatusDot(MagziOpsStatusMap.dot(status), size: 7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MagziDesign.Spacing.s) {
                    Text(time)
                        .foregroundStyle(MagziDesign.labelTertiary)
                    Text(title.isEmpty ? "event" : title)
                        .fontWeight(.semibold)
                        .foregroundStyle(status == "error" ? MagziDesign.rose : MagziDesign.label)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if live {
                        Text("bus")
                            .foregroundStyle(MagziDesign.mint)
                    }
                }
                .font(MagziDesign.Typography.mono)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                if let tag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(MagziDesign.labelTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, MagziDesign.Spacing.s)
        .accessibilityElement(children: .combine)
    }
}
