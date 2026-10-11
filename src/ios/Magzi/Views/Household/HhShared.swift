import Combine
import SwiftUI
import UIKit

// Shared helpers for the Household tab. All types use the `Hh` prefix.

/// Pushed screens under the Household root.
enum HhRoute: Hashable {
    case items
    case item(MagziItem)
    case rota
    case meals
    case bills
    case approvals
    case reality
    case thread
    case facts
    case activity
    case summary
    case members
}

// MARK: - Errors

enum HhErrors {
    /// User-facing copy. Server 403/400 bodies are human sentences, so they pass through.
    static func message(_ error: Error) -> String {
        if let e = error as? MagziError {
            switch e {
            case .transport:
                return "Couldn't reach Magzi. Check you're on the home network or Tailscale."
            default:
                return e.localizedDescription
            }
        }
        return error.localizedDescription
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        if case .transport(let message)? = error as? MagziError, message.lowercased().contains("cancelled") { return true }
        return false
    }

    static func status(_ error: Error) -> Int? { (error as? MagziError)?.statusCode }
}

// MARK: - Haptics

enum HhHaptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Formatting

enum HhFormat {
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInTomorrow(date) { return "tomorrow" }
        if cal.isDateInYesterday(date) { return "yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        if days > 0 && days < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func due(_ ms: MagziMs?, hasTime: Bool = false) -> String? {
        guard let ms else { return nil }
        let date = ms.magziDate
        let day = relativeDay(date)
        return hasTime ? "\(day) \(date.formatted(date: .omitted, time: .shortened))" : day
    }

    static func time(_ ms: MagziMs?) -> String {
        guard let ms else { return "" }
        let date = ms.magziDate
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    static func shortDate(_ ms: MagziMs?) -> String {
        guard let ms else { return "—" }
        return ms.magziDate.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    static func capitalized(_ s: String?) -> String {
        guard let s = s?.magziNonEmpty else { return "" }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// ISO week string `YYYY-Www` for a date.
    static func isoWeek(_ date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 2000, c.weekOfYear ?? 1)
    }

    static func weekNumber(_ date: Date) -> Int {
        Calendar(identifier: .iso8601).component(.weekOfYear, from: date)
    }

    /// Value for `progress {action: schedule, when}`. Locale-independent.
    static func whenString(_ date: Date) -> String {
        // RFC 3339 with offset: a bare "yyyy-MM-dd HH:mm" is read in the household's zone, not the phone's.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f.string(from: date)
    }

    /// Parses an API amount string ("42", "£42.50", "12.99 GBP") into a number when possible.
    static func amountValue(_ amount: String?) -> Double? {
        guard let amount = amount?.magziNonEmpty else { return nil }
        let cleaned = amount.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(cleaned)
    }

    /// Formats a bill amount; keeps any explicit currency symbol the server sent.
    static func amount(_ amount: String?) -> String? {
        guard let raw = amount?.trimmingCharacters(in: .whitespaces).magziNonEmpty else { return nil }
        guard let value = amountValue(raw) else { return raw }
        let symbol = raw.first(where: { "£$€¥₹".contains($0) }).map(String.init)
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        if let symbol { f.currencySymbol = symbol }
        return f.string(from: NSNumber(value: value)) ?? raw
    }

    static func currencyTotal(_ value: Double, sample: String?) -> String {
        let symbol = sample?.first(where: { "£$€¥₹".contains($0) }).map(String.init)
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        if let symbol { f.currencySymbol = symbol }
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

/// Member tints in order (fair load bars, thread speaker names).
enum HhPalette {
    static let colors: [Color] = [MagziDesign.mint, MagziDesign.blue, MagziDesign.violet, MagziDesign.amber, MagziDesign.rose]

    static func color(for index: Int) -> Color { colors[abs(index) % colors.count] }

    static func color(for name: String, in names: [String]) -> Color {
        if let i = names.firstIndex(of: name) { return color(for: i) }
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return color(for: hash)
    }

    static func presenceStatus(_ state: String?) -> MagziStatus? {
        switch state?.lowercased() {
        case "home": return .ok
        case "away": return .attention
        case nil, "", "unknown": return nil
        default: return .off
        }
    }
}

// MARK: - Identity

enum HhIdentity {
    /// Names that refer to the signed-in person (rota/thread speaker matching).
    @MainActor static var myNames: Set<String> {
        let hub = MagziHub.shared
        var names = Set<String>()
        if let n = hub.person?.displayName?.magziNonEmpty { names.insert(n.lowercased()) }
        if let n = hub.user?.displayName?.magziNonEmpty { names.insert(n.lowercased()) }
        return names
    }

    @MainActor static func isMe(_ name: String?) -> Bool {
        guard let name = name?.lowercased().magziNonEmpty else { return false }
        return myNames.contains(name)
    }
}

/// Household member names, gathered from rota + presence (the API has no member list endpoint).
enum HhMembers {
    @MainActor
    static func load(householdId: String) async -> [String] {
        let api = MagziAPI.shared
        async let rota = try? api.rota(householdId: householdId)
        async let presence = try? api.presence(householdId: householdId)
        let (r, p) = await (rota, presence)
        var names: [String] = []
        for n in (r?.people ?? []) + (p ?? []).compactMap(\.name) where !n.isEmpty && !names.contains(n) {
            names.append(n)
        }
        return names
    }
}

// MARK: - Components

struct HhErrorCard: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
            MagziStatusDot(.problem)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                Text(message)
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.label)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button("Try again", action: retry)
                        .buttonStyle(MagziCompactButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .magziCard()
    }
}

struct HhAvatar: View {
    let name: String
    var size: CGFloat = 32
    var tint: Color = MagziDesign.labelSecondary

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(MagziDesign.surfaceSecondary))
            .accessibilityHidden(true)
    }
}

/// Simple horizontal share bar.
struct HhBar: View {
    let fraction: Double
    var tint: Color = MagziDesign.mint
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(MagziDesign.surfaceSecondary)
                Capsule().fill(tint)
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(MagziDesign.Motion.gentle, value: fraction)
    }
}

// MARK: - Undo toast

struct HhToast: Identifiable {
    let id = UUID()
    var text: String
    var undo: (() async -> Void)?
}

private struct HhToastModifier: ViewModifier {
    @Binding var toast: HhToast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: MagziDesign.Spacing.m) {
                    Text(toast.text)
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.label)
                        .lineLimit(2)
                    Spacer(minLength: MagziDesign.Spacing.s)
                    if let undo = toast.undo {
                        Button("Undo") {
                            self.toast = nil
                            Task { await undo() }
                        }
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(MagziDesign.mint)
                    }
                }
                .padding(.horizontal, MagziDesign.Spacing.l)
                .padding(.vertical, MagziDesign.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MagziDesign.surfaceElevated)
                )
                .magziShadow(MagziDesign.Shadows.floating)
                .padding(.horizontal, MagziDesign.Spacing.gutter)
                .padding(.bottom, MagziDesign.Spacing.m)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if self.toast?.id == toast.id {
                        withAnimation(MagziDesign.Motion.standard) { self.toast = nil }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : MagziDesign.Motion.standard, value: toast?.id)
    }
}

/// Live refresh helper: runs `action` when the hub reports a change for `householdId`.
private struct HhHouseholdChangeModifier: ViewModifier {
    let householdId: String
    let action: () async -> Void

    func body(content: Content) -> some View {
        content.onReceive(MagziHub.shared.householdChanged.receive(on: DispatchQueue.main)) { id in
            guard id == householdId else { return }
            Task { await action() }
        }
    }
}

extension View {
    func hhToast(_ toast: Binding<HhToast?>) -> some View {
        modifier(HhToastModifier(toast: toast))
    }

    func hhOnHouseholdChange(_ householdId: String, perform action: @escaping () async -> Void) -> some View {
        modifier(HhHouseholdChangeModifier(householdId: householdId, action: action))
    }

    /// Grouped list chrome per spec.
    func hhListChrome() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MagziDesign.background.ignoresSafeArea())
    }
}

// MARK: - Pickers / sheets

/// Member picker (delegate / swap).
struct HhMemberPicker: View {
    let title: String
    let householdId: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var members: [String] = []
    @State private var loading = true
    @State private var custom = ""

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    Section {
                        ForEach(0..<3, id: \.self) { _ in Text("Member name").redacted(reason: .placeholder) }
                    }
                } else if !members.isEmpty {
                    Section("Members") {
                        ForEach(members, id: \.self) { name in
                            Button {
                                onPick(name)
                                dismiss()
                            } label: {
                                HStack(spacing: MagziDesign.Spacing.m) {
                                    HhAvatar(name: name)
                                    Text(name).foregroundStyle(MagziDesign.label)
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("Someone else", text: $custom)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(pickCustom)
                    Button("Use this name", action: pickCustom)
                        .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    if !loading && members.isEmpty {
                        Text("Couldn't load the member list. Type a name instead.")
                    }
                }
            }
            .hhListChrome()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                members = await HhMembers.load(householdId: householdId)
                loading = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pickCustom() {
        let name = custom.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onPick(name)
        dismiss()
    }
}

/// Graphical date picker sheet (schedule / unpark).
struct HhDateSheet: View {
    let title: String
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Date()).map {
        Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: $0) ?? $0
    } ?? Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker("When", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .tint(MagziDesign.mint)
                    .padding(.horizontal, MagziDesign.Spacing.gutter)
            }
            .magziScreenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        onPick(date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
