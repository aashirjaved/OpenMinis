import SwiftUI

/// Approvals: approve / deny. Non-admins are mapped to role guest server-side (403), so
/// buttons only show for admins; anyone else gets an explanation.
struct HhApprovalsView: View {
    let householdId: String

    @ObservedObject private var hub = MagziHub.shared
    @State private var approvals: [MagziApproval]?
    @State private var decided: [MagziApproval] = []
    @State private var error: String?
    @State private var rowErrors: [Int64: String] = [:]
    @State private var working: Set<Int64> = []
    @State private var expanded: Set<Int64> = []

    var body: some View {
        List {
            if !hub.isAdmin {
                Section {
                    Label("Only household admins can approve or deny. You can see what's waiting.", systemImage: "info.circle")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
            }
            if let error, approvals == nil {
                Section { HhErrorCard(message: error) { Task { await load() } } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if let approvals {
                let pending = approvals.filter(\.isPending)
                if pending.isEmpty && decided.isEmpty {
                    Section {
                        MagziEmptyState(
                            systemImage: "checkmark.shield",
                            title: "No approvals waiting",
                            message: "When Magzi needs a yes before acting, it shows up here."
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                }
                if !pending.isEmpty {
                    Section("Waiting") {
                        ForEach(pending) { card($0) }
                    }
                }
                if !decided.isEmpty {
                    Section("Recently decided") {
                        ForEach(decided) { a in
                            HStack {
                                Text(a.summary ?? "Approval")
                                    .font(MagziDesign.Typography.subheadline)
                                    .foregroundStyle(MagziDesign.labelSecondary)
                                Spacer()
                                MagziPill(
                                    title: a.status == "approved" ? "Approved" : a.status == "denied" ? "Denied" : HhFormat.capitalized(a.status),
                                    tint: a.status == "approved" ? MagziDesign.mint : MagziDesign.labelSecondary
                                )
                            }
                        }
                    }
                }
            } else {
                Section {
                    ForEach(0..<2, id: \.self) { _ in
                        MagziRow(title: "Send the group a message", subtitle: "Requested by Sara · 2 min ago", systemImage: "checkmark.shield")
                    }
                }
                .redacted(reason: .placeholder)
            }
        }
        .hhListChrome()
        .navigationTitle("Approvals")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .hhOnHouseholdChange(householdId) { await load() }
    }

    private func card(_ a: MagziApproval) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
                MagziIconBadge(systemImage: "checkmark.shield", tint: MagziDesign.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.summary?.magziNonEmpty ?? HhFormat.capitalized(a.kind ?? "Approval"))
                        .font(MagziDesign.Typography.headline)
                        .foregroundStyle(MagziDesign.label)
                    if let preview = a.preview?.magziNonEmpty {
                        Text(preview)
                            .font(MagziDesign.Typography.subheadline)
                            .foregroundStyle(MagziDesign.labelSecondary)
                            .lineLimit(expanded.contains(a.id) ? nil : 4)
                        if preview.count > 180 && !expanded.contains(a.id) {
                            Button("More") { expanded.insert(a.id) }
                                .font(MagziDesign.Typography.footnote)
                                .foregroundStyle(MagziDesign.mint)
                                .buttonStyle(.plain)
                        }
                    }
                    Text(meta(a))
                        .font(MagziDesign.Typography.caption)
                        .foregroundStyle(MagziDesign.labelTertiary)
                }
            }
            if hub.isAdmin {
                HStack(spacing: MagziDesign.Spacing.m) {
                    Button("Deny") { Task { await decide(a, approve: false) } }
                        .buttonStyle(MagziSecondaryButtonStyle())
                    Button("Approve") { Task { await decide(a, approve: true) } }
                        .buttonStyle(MagziPrimaryButtonStyle())
                }
                .disabled(working.contains(a.id))
            }
            if let rowError = rowErrors[a.id] {
                Text(rowError)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.rose)
            }
        }
        .padding(.vertical, MagziDesign.Spacing.s)
    }

    private func meta(_ a: MagziApproval) -> String {
        var parts: [String] = []
        if let by = a.requestedBy?.magziNonEmpty {
            parts.append("Requested by \(by)" + (a.requestedByRole.map { " (\($0))" } ?? ""))
        }
        if let exp = a.expires, exp > 0 {
            parts.append("expires \(exp.magziDate.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        do {
            let list = try await MagziAPI.shared.approvals(householdId: householdId)
            withAnimation(MagziDesign.Motion.standard) { approvals = list }
            error = nil
        } catch {
            if HhErrors.isCancellation(error) { return }
            self.error = HhErrors.message(error)
        }
    }

    private func decide(_ a: MagziApproval, approve: Bool) async {
        working.insert(a.id)
        defer { working.remove(a.id) }
        do {
            let result = approve ? try await MagziAPI.shared.approve(id: a.id) : try await MagziAPI.shared.deny(id: a.id)
            approve ? HhHaptics.success() : HhHaptics.medium()
            var done = result ?? a
            if done.isPending { done.status = approve ? "approved" : "denied" }
            rowErrors[a.id] = nil
            withAnimation(MagziDesign.Motion.standard) {
                approvals?.removeAll { $0.id == a.id }
                decided.insert(done, at: 0)
            }
            await hub.refreshApprovalsCount()
        } catch {
            HhHaptics.error()
            rowErrors[a.id] = HhErrors.status(error) == 403
                ? "Only household admins can decide this. \(HhErrors.message(error))"
                : HhErrors.message(error)
        }
    }
}
