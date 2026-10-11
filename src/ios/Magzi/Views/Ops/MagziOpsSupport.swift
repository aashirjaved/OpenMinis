import SwiftUI
import UIKit

// Shared state + small building blocks for the Ops cockpit (spec §4.9).

// MARK: - Sections

enum MagziOpsSection: String, CaseIterable, Identifiable {
    case overview, capabilities, usage, sessions, live, config, improve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .capabilities: return "Capabilities"
        case .usage: return "Usage"
        case .sessions: return "Sessions"
        case .live: return "Live"
        case .config: return "Config"
        case .improve: return "Improve"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .capabilities: return "puzzlepiece.extension"
        case .usage: return "chart.bar"
        case .sessions: return "text.bubble"
        case .live: return "dot.radiowaves.left.and.right"
        case .config: return "slider.horizontal.3"
        case .improve: return "hammer"
        }
    }
}

// MARK: - Store

@MainActor
final class MagziOpsStore: ObservableObject {
    static let networkErrorCopy = "Couldn't reach Magzi. Check you're on the home network or Tailscale."

    @Published var state: MagziCockpitState?
    @Published var stateError: String?
    @Published var stateLoading = false

    @Published var usage: MagziUsageResponse?
    @Published var usageError: String?
    @Published var usageLoading = false

    @Published var sessions: [MagziCockpitSession]?
    @Published var sessionsError: String?
    @Published var sessionsLoading = false

    @Published var instructions: [MagziInstruction]?
    @Published var instructionsError: String?
    @Published var instructionsLoading = false

    /// Last `POST /api/config` result (kept so the operator can roll back).
    @Published var lastConfigChange: MagziOpsConfigChange?

    /// Failure of a one-shot action (pause, restart, allow…), shown as an alert.
    @Published var actionError: String?
    /// Same as `actionError`, but for actions started from a sheet (shown inside the sheet).
    @Published var sheetError: String?
    /// Set when any call came back 401: the cockpit token lives in daemon memory only.
    @Published var sessionEnded = false

    let api = MagziCockpitAPI.shared

    func reset() {
        state = nil; stateError = nil
        usage = nil; usageError = nil
        sessions = nil; sessionsError = nil
        instructions = nil; instructionsError = nil
        lastConfigChange = nil
        actionError = nil
        sheetError = nil
    }

    /// Maps an error to user copy. Returns nil for 401 (flags `sessionEnded`) and cancellations.
    func message(for error: Error) -> String? {
        if error is CancellationError || Task.isCancelled { return nil }
        if let urlError = error as? URLError, urlError.code == .cancelled { return nil }
        if let magzi = error as? MagziError {
            switch magzi {
            case .unauthorized, .notConfigured:
                sessionEnded = true
                return nil
            case .transport:
                return Self.networkErrorCopy
            case .http(403, _):
                return "The cockpit refused this action (403). Owner access is required."
            default:
                return magzi.localizedDescription
            }
        }
        if error is URLError { return Self.networkErrorCopy }
        return error.localizedDescription
    }

    /// Runs a one-shot action; haptics + alert on failure. Returns true on success.
    @discardableResult
    func act(inSheet: Bool = false, _ operation: @MainActor () async throws -> Void) async -> Bool {
        if inSheet { sheetError = nil }
        do {
            try await operation()
            MagziOpsHaptics.success()
            return true
        } catch {
            if let text = message(for: error) {
                if inSheet { sheetError = text } else { actionError = text }
                MagziOpsHaptics.error()
            }
            return false
        }
    }

    func loadState() async {
        stateLoading = true
        defer { stateLoading = false }
        do {
            state = try await api.state()
            stateError = nil
        } catch {
            if let text = message(for: error) { stateError = text }
        }
    }

    func loadUsage(limit: Int = 100) async {
        usageLoading = true
        defer { usageLoading = false }
        do {
            usage = try await api.usage(limit: limit)
            usageError = nil
        } catch {
            if let text = message(for: error) { usageError = text }
        }
    }

    func loadSessions() async {
        sessionsLoading = true
        defer { sessionsLoading = false }
        do {
            sessions = try await api.sessions(limit: 100)
            sessionsError = nil
        } catch {
            if let text = message(for: error) { sessionsError = text }
        }
    }

    func loadInstructions() async {
        instructionsLoading = true
        defer { instructionsLoading = false }
        do {
            instructions = try await api.adminInstructions()
            instructionsError = nil
        } catch {
            if let text = message(for: error) { instructionsError = text }
        }
    }
}

struct MagziOpsConfigChange: Equatable {
    var key: MagziConfigKey
    var value: String
    var restartRequired: Bool
    var rollbackHash: String?
    var rolledBack = false
}

// MARK: - Formatting

enum MagziOpsFormat {
    static func tokens(_ value: Int64?) -> String {
        guard let value else { return "–" }
        let v = Double(value)
        switch abs(v) {
        case 1_000_000_000...: return String(format: "%.1fB", v / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000)
        case 10_000...: return String(format: "%.0fk", v / 1_000)
        case 1_000...: return String(format: "%.1fk", v / 1_000)
        default: return "\(value)"
        }
    }

    static func tokens(_ value: Double?) -> String {
        guard let value else { return "–" }
        return tokens(Int64(value.rounded()))
    }

    static func cost(_ value: Double?) -> String {
        guard let value else { return "–" }
        if value == 0 { return "$0" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        return String(format: "$%.2f", value)
    }

    static func megabytes(_ value: Double?) -> String {
        guard let value else { return "–" }
        if value >= 1024 { return String(format: "%.1f GB", value / 1024) }
        return String(format: "%.0f MB", value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.0f%%", value)
    }

    static func date(ms: MagziMs?) -> Date? {
        guard let ms, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlainFormatter = ISO8601DateFormatter()

    static func relative(ms: MagziMs?) -> String {
        guard let date = date(ms: ms) else { return "–" }
        return relative(date)
    }

    static func relative(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 5 { return "now" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func clock(ms: MagziMs?) -> String {
        guard let date = date(ms: ms) else { return "--:--:--" }
        return clockFormatter.string(from: date)
    }

    /// Audit `time` strings are RFC 3339 / SQLite timestamps; fall back to the raw string.
    static func clock(_ string: String?) -> String {
        guard let string, !string.isEmpty else { return "--:--:--" }
        if let date = parse(string) { return clockFormatter.string(from: date) }
        return string
    }

    static func relative(_ string: String?) -> String? {
        guard let string, let date = parse(string) else { return string }
        return relative(date)
    }

    static func parse(_ string: String) -> Date? {
        if let d = isoFormatter.date(from: string) ?? isoPlainFormatter.date(from: string) { return d }
        let sqlite = DateFormatter()
        sqlite.locale = Locale(identifier: "en_US_POSIX")
        sqlite.timeZone = TimeZone(identifier: "UTC")
        sqlite.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return sqlite.date(from: String(string.prefix(19)))
    }

    /// Rust Debug strings ("ProductionActive", "awaiting_approval") → "Production active".
    static func humanize(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "–" }
        var words: [String] = []
        var current = ""
        for ch in raw {
            if ch == "_" || ch == "-" || ch == " " {
                if !current.isEmpty { words.append(current); current = "" }
            } else if ch.isUppercase, !current.isEmpty, current.last?.isUppercase == false {
                words.append(current)
                current = String(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.map { $0.lowercased() }.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// `whatsapp:+44…` → `whatsapp`.
    static func channel(of conversation: String) -> String? {
        guard let idx = conversation.firstIndex(of: ":") else { return nil }
        let prefix = String(conversation[..<idx])
        return prefix.isEmpty ? nil : prefix
    }

    static func compact(_ json: JSONValue) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: json.anyValue, options: [.fragmentsAllowed, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "…" }
        return string
    }
}

enum MagziOpsStatusMap {
    /// ok / error / skipped / running → dot.
    static func dot(_ status: String?) -> MagziStatus {
        switch status?.lowercased() {
        case "ok", "success", "completed", "done": return .ok
        case "error", "failed", "failure": return .problem
        case "running", "pending", "started": return .live
        case "skipped", nil: return .off
        default: return .attention
        }
    }

    static func feature(_ state: String?) -> MagziStatus {
        switch state {
        case "on": return .ok
        case "attention": return .attention
        default: return .off
        }
    }
}

// MARK: - Haptics

enum MagziOpsHaptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

// MARK: - Components

/// Scroll container used by every pane: gutter, section spacing, pull to refresh.
struct MagziOpsPane<Content: View>: View {
    let refresh: () async -> Void
    let content: Content

    init(refresh: @escaping () async -> Void, @ViewBuilder content: () -> Content) {
        self.refresh = refresh
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MagziDesign.Spacing.xl) {
                content
            }
            .padding(.horizontal, MagziDesign.Spacing.gutter)
            .padding(.top, MagziDesign.Spacing.l)
            .padding(.bottom, MagziDesign.Spacing.xxxl)
        }
        .refreshable { await refresh() }
    }
}

/// Inline error card: problem dot, one line, "Try again".
struct MagziOpsErrorCard: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MagziDesign.Spacing.m) {
            MagziStatusDot(.problem)
            Text(message)
                .font(MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: MagziDesign.Spacing.s)
            Button("Try again") { Task { await retry() } }
                .buttonStyle(MagziCompactButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .magziCard()
    }
}

/// Horizontally scrolling segmented control (7 panes don't fit a system segmented picker).
struct MagziOpsSectionBar: View {
    @Binding var selection: MagziOpsSection
    @Namespace private var namespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MagziDesign.Spacing.xs) {
                    ForEach(MagziOpsSection.allCases) { section in
                        let selected = section == selection
                        Button {
                            guard selection != section else { return }
                            MagziOpsHaptics.selection()
                            withAnimation(MagziDesign.Motion.quick) { selection = section }
                        } label: {
                            Text(section.title)
                                .font(.system(.subheadline, design: .default, weight: .semibold))
                                .foregroundStyle(selected ? MagziDesign.onAccent : MagziDesign.labelSecondary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 34)
                                .background {
                                    if selected {
                                        Capsule(style: .continuous)
                                            .fill(MagziDesign.mint)
                                            .matchedGeometryEffect(id: "ops.section", in: namespace)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(section)
                        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(MagziDesign.Spacing.xs)
                .background(Capsule(style: .continuous).fill(MagziDesign.surfaceSecondary))
                .padding(.horizontal, MagziDesign.Spacing.gutter)
                .padding(.vertical, MagziDesign.Spacing.s)
            }
            .onChange(of: selection) { value in
                withAnimation(MagziDesign.Motion.standard) { proxy.scrollTo(value, anchor: .center) }
            }
        }
        .background(MagziDesign.background)
    }
}

/// Label + value line inside a card.
struct MagziOpsKeyValue: View {
    let label: String
    let value: String
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MagziDesign.Spacing.m) {
            Text(label)
                .font(MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.labelSecondary)
            Spacer(minLength: MagziDesign.Spacing.s)
            Text(value)
                .font(mono ? MagziDesign.Typography.mono : MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.label)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

/// Thin horizontal share bar (usage by model).
struct MagziOpsShareBar: View {
    let fraction: Double
    var tint: Color = MagziDesign.mint
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(MagziDesign.surfaceSecondary)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(4, geo.size.width * CGFloat(shown ? min(max(fraction, 0), 1) : 0)))
            }
        }
        .frame(height: 6)
        .onAppear { withAnimation(MagziDesign.Motion.gentle) { shown = true } }
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Hairline between rows inside a card.
struct MagziOpsDivider: View {
    var body: some View {
        Rectangle().fill(MagziDesign.hairline).frame(height: 1)
    }
}

/// Single-field sheet used by Approve (head sha) and Accept (commit).
struct MagziOpsFieldSheet: View {
    let title: String
    let message: String
    let fieldLabel: String
    let actionTitle: String
    let error: String?
    let submit: (String) async -> Bool

    @State private var value: String
    @State private var isWorking = false
    @Environment(\.dismiss) private var dismiss

    init(title: String, message: String, fieldLabel: String, initialValue: String, actionTitle: String, error: String?, submit: @escaping (String) async -> Bool) {
        self.error = error
        self.title = title
        self.message = message
        self.fieldLabel = fieldLabel
        self.actionTitle = actionTitle
        self.submit = submit
        _value = State(initialValue: initialValue)
    }

    private var trimmed: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MagziDesign.Spacing.l) {
                    Text(message)
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.labelSecondary)
                    VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                        Text(fieldLabel.uppercased())
                            .font(MagziDesign.Typography.eyebrow)
                            .foregroundStyle(MagziDesign.labelTertiary)
                        TextField(fieldLabel, text: $value)
                            .font(MagziDesign.Typography.mono)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(MagziDesign.Spacing.m)
                            .background(
                                RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous)
                                    .fill(MagziDesign.surfaceSecondary)
                            )
                    }
                    if let error {
                        Text(error)
                            .font(MagziDesign.Typography.footnote)
                            .foregroundStyle(MagziDesign.rose)
                    }
                    Button {
                        Task {
                            isWorking = true
                            let ok = await submit(trimmed)
                            isWorking = false
                            if ok { dismiss() }
                        }
                    } label: {
                        if isWorking { ProgressView() } else { Text(actionTitle) }
                    }
                    .buttonStyle(MagziPrimaryButtonStyle())
                    .disabled(trimmed.isEmpty || isWorking)
                }
                .padding(MagziDesign.Spacing.gutter)
            }
            .magziScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
