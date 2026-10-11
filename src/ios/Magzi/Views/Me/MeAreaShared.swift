import SwiftUI
import UIKit

// Small helpers shared by the Me and Admin screens. Prefixed `MeArea` to avoid collisions.

/// Friendly copy for API failures on Me/Admin screens.
enum MeAreaFailure {
    enum Kind { case unlinked, switchedOff, forbidden, offline, other }

    static let offlineCopy = "Couldn't reach Magzi. Check you're on the home network or Tailscale."
    static let unlinkedCopy = "This login isn't linked to a household member yet. Send Magzi your link code on WhatsApp, then come back."

    static func kind(_ error: Error) -> Kind {
        guard let e = error as? MagziError else { return .offline }
        switch e {
        case .http(409, _): return .unlinked
        case .http(403, let message):
            let m = message.lowercased()
            return (m.contains("sharing is off") || m.contains("nothing was stored") || m.contains("switch")) ? .switchedOff : .forbidden
        case .transport: return .offline
        default: return .other
        }
    }

    static func message(_ error: Error) -> String {
        switch kind(error) {
        case .unlinked: return unlinkedCopy
        case .switchedOff:
            if case .http(_, let m) = error as? MagziError, !m.isEmpty { return "\(m) You can turn it on in Privacy." }
            return "That's switched off in Privacy, so Magzi has nothing to show here."
        case .forbidden:
            if case .http(_, let m) = error as? MagziError, !m.isEmpty, m != "admin only", m != "admin required" { return m }
            return "This needs an admin login."
        case .offline: return offlineCopy
        case .other: return error.localizedDescription
        }
    }

    static func isUnauthorized(_ error: Error) -> Bool { (error as? MagziError) == .unauthorized }
}

/// Inline error card: status dot, one-line message, "Try again".
struct MeAreaErrorCard: View {
    let error: Error
    var retry: (() -> Void)?

    private var kind: MeAreaFailure.Kind { MeAreaFailure.kind(error) }

    var body: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            HStack(alignment: .top, spacing: MagziDesign.Spacing.s) {
                switch kind {
                case .unlinked:
                    Image(systemName: "link").foregroundStyle(MagziDesign.amber).font(.subheadline.weight(.semibold))
                case .switchedOff, .forbidden:
                    Image(systemName: "hand.raised").foregroundStyle(MagziDesign.amber).font(.subheadline.weight(.semibold))
                default:
                    MagziStatusDot(.problem)
                }
                Text(MeAreaFailure.message(error))
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let retry, kind == .offline || kind == .other || kind == .unlinked {
                Button("Try again", action: retry)
                    .buttonStyle(MagziCompactButtonStyle())
            }
        }
        .magziCard()
    }
}

/// Lightweight inline banner for action failures (keeps content visible).
struct MeAreaBanner: View {
    let text: String
    var tint: Color = MagziDesign.rose
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: MagziDesign.Spacing.s) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(tint)
            Text(text)
                .font(MagziDesign.Typography.footnote)
                .foregroundStyle(MagziDesign.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(MagziDesign.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(MagziDesign.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous).fill(tint.opacity(0.10)))
    }
}

enum MeAreaHaptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

enum MeAreaFormat {
    static func minutes(_ value: Double?) -> String {
        let total = Int((value ?? 0).rounded())
        let sign = total < 0 ? "−" : ""
        let m = abs(total)
        if m < 60 { return "\(sign)\(m)m" }
        return m % 60 == 0 ? "\(sign)\(m / 60)h" : "\(sign)\(m / 60)h \(m % 60)m"
    }

    static func time(_ ms: MagziMs?) -> String {
        guard let ms else { return "–" }
        return ms.magziDate.formatted(date: .omitted, time: .shortened)
    }

    static func dateTime(_ ms: MagziMs?) -> String {
        guard let ms, ms > 0 else { return "Never" }
        return ms.magziDate.formatted(date: .abbreviated, time: .shortened)
    }

    static func relative(_ ms: MagziMs?) -> String {
        guard let ms, ms > 0 else { return "Never" }
        return RelativeDateTimeFormatter().localizedString(for: ms.magziDate, relativeTo: Date())
    }

    static func duration(ms: Int64) -> String {
        let s = max(0, ms / 1000)
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func humanize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// "HH:MM" ⇄ Date (today).
    static func date(fromHHMM s: String, fallbackHour: Int) -> Date {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = parts.count == 2 ? parts[0] : fallbackHour
        c.minute = parts.count == 2 ? parts[1] : 0
        return Calendar.current.date(from: c) ?? Date()
    }

    static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// Category tints shared by My week and Timeline.
enum MeAreaCategory {
    static func tint(_ key: String?) -> Color {
        let k = (key ?? "").lowercased()
        if k.contains("work") || k.contains("school") || k.contains("commute") { return MagziDesign.blue }
        if k.contains("home") || k.contains("chore") || k.contains("errand") { return MagziDesign.mint }
        if k.contains("family") || k.contains("kid") || k.contains("school_run") { return MagziDesign.violet }
        if k.contains("health") || k.contains("gym") || k.contains("sport") || k.contains("workout") { return MagziDesign.rose }
        if k.contains("eat") || k.contains("food") || k.contains("social") { return MagziDesign.amber }
        return MagziDesign.labelTertiary
    }

    static func placeSymbol(_ kind: String?) -> String {
        switch (kind ?? "").lowercased() {
        case "home": return "house"
        case "work": return "briefcase"
        case "gym": return "figure.run"
        case "school": return "graduationcap"
        case "restaurant": return "fork.knife"
        case "cafe": return "cup.and.saucer"
        case "shop": return "cart"
        case "gp": return "cross.case"
        case "family": return "person.2"
        case "sensitive": return "lock"
        default: return "mappin"
        }
    }
}

/// Screen scaffold used by the Me/Admin scroll screens.
struct MeAreaScroll<Content: View>: View {
    let refresh: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MagziDesign.Spacing.section) {
                content()
            }
            .padding(.horizontal, MagziDesign.Spacing.gutter)
            .padding(.vertical, MagziDesign.Spacing.l)
        }
        .refreshable { await refresh() }
        .magziScreenBackground()
    }
}
