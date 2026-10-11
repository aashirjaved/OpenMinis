import SwiftUI

/// Self-built capabilities (`state.capabilities`) with a disable action.
struct MagziOpsCapabilitiesPane: View {
    @ObservedObject var store: MagziOpsStore

    @State private var pendingDisable: MagziCapability?
    @State private var working: String?

    var body: some View {
        MagziOpsPane(refresh: { await store.loadState() }) {
            if let error = store.stateError, store.state == nil {
                MagziOpsErrorCard(message: error, retry: { await store.loadState() })
            } else if let state = store.state {
                let caps = sorted(state.capabilities ?? [])
                if let error = store.stateError {
                    MagziOpsErrorCard(message: error, retry: { await store.loadState() })
                }
                if caps.isEmpty {
                    MagziEmptyState(
                        systemImage: "puzzlepiece.extension",
                        title: "No capabilities yet",
                        message: "Tools Magzi builds for itself show up here once they're drafted."
                    )
                } else {
                    MagziSectionHeader("\(caps.filter(\.isActive).count) active · \(caps.count) total")
                    ForEach(caps) { cap in card(cap) }
                }
            } else {
                ForEach(Self.placeholders) { card($0) }
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
            }
        }
        .task { if store.state == nil { await store.loadState() } }
        .confirmationDialog(
            "Disable \(pendingDisable?.toolName ?? "capability")?",
            isPresented: Binding(get: { pendingDisable != nil }, set: { if !$0 { pendingDisable = nil } }),
            titleVisibility: .visible,
            presenting: pendingDisable
        ) { cap in
            Button("Disable", role: .destructive) { Task { await disable(cap) } }
        } message: { _ in
            Text("Magzi stops using this tool immediately. Re-enabling needs a new approval.")
        }
    }

    private func sorted(_ caps: [MagziCapability]) -> [MagziCapability] {
        caps.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            if lhs.isDisabled != rhs.isDisabled { return !lhs.isDisabled }
            return (lhs.toolName ?? lhs.id) < (rhs.toolName ?? rhs.id)
        }
    }

    private func card(_ cap: MagziCapability) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(cap.toolName ?? cap.id)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(cap.isDisabled ? MagziDesign.labelSecondary : MagziDesign.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: MagziDesign.Spacing.s)
                MagziPill(title: MagziOpsFormat.humanize(cap.status), tint: statusTint(cap.status))
            }
            if let need = cap.sourceUserNeed, !need.isEmpty {
                Text(need)
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .lineLimit(3)
            }
            HStack(spacing: MagziDesign.Spacing.s) {
                if let risk = cap.riskLevel {
                    MagziPill(title: "\(MagziOpsFormat.humanize(risk)) risk", systemImage: "exclamationmark.shield", tint: riskTint(risk))
                }
                if let when = cap.activatedAt ?? cap.approvedAt ?? cap.createdAt {
                    Text(MagziOpsFormat.relative(when) ?? when)
                        .font(MagziDesign.Typography.caption)
                        .foregroundStyle(MagziDesign.labelTertiary)
                }
                Spacer()
                if working == cap.id {
                    ProgressView()
                } else if !cap.isDisabled {
                    Button("Disable") { pendingDisable = cap }
                        .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.rose))
                }
            }
            if let path = cap.extensionPath {
                Text(path)
                    .font(MagziDesign.Typography.mono)
                    .foregroundStyle(MagziDesign.labelTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if let by = cap.approvedBy {
                Text("Approved by \(by)\(cap.approvalReason.map { " · \($0)" } ?? "")")
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .lineLimit(2)
            }
        }
        .magziCard()
    }

    private func statusTint(_ status: String?) -> Color {
        switch status {
        case "active": return MagziDesign.mint
        case "disabled": return MagziDesign.labelTertiary
        case "approval_required": return MagziDesign.amber
        case "validation_failed": return MagziDesign.rose
        default: return MagziDesign.blue
        }
    }

    private func riskTint(_ risk: String) -> Color {
        switch risk {
        case "high": return MagziDesign.rose
        case "medium": return MagziDesign.amber
        default: return MagziDesign.mint
        }
    }

    private func disable(_ cap: MagziCapability) async {
        working = cap.id
        defer { working = nil }
        await store.act {
            let updated = try await store.api.disableCapability(tool: cap.toolName ?? cap.id)
            if var caps = store.state?.capabilities, let idx = caps.firstIndex(where: { $0.id == updated.id || $0.id == cap.id }) {
                caps[idx] = updated
                store.state?.capabilities = caps
            }
        }
    }

    private static let placeholders: [MagziCapability] = (0..<3).map {
        MagziCapability(id: "placeholder-\($0)", toolName: "capability_tool_name", status: "active", sourceUserNeed: "A placeholder need that describes what the tool does", riskLevel: "low")
    }
}
