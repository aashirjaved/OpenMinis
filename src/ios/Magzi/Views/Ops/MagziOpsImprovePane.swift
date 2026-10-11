import SwiftUI

/// Improve: admin instruction queue (submit / approve / accept).
struct MagziOpsImprovePane: View {
    @ObservedObject var store: MagziOpsStore

    @State private var showComposer = false
    @State private var approving: MagziInstruction?
    @State private var accepting: MagziInstruction?

    var body: some View {
        MagziOpsPane(refresh: { await store.loadInstructions() }) {
            Button {
                store.sheetError = nil
                showComposer = true
            } label: {
                Label("New instruction", systemImage: "plus")
            }
            .buttonStyle(MagziPrimaryButtonStyle())

            if let error = store.instructionsError, store.instructions == nil {
                MagziOpsErrorCard(message: error, retry: { await store.loadInstructions() })
            } else if let list = store.instructions {
                if let error = store.instructionsError {
                    MagziOpsErrorCard(message: error, retry: { await store.loadInstructions() })
                }
                if list.isEmpty {
                    MagziEmptyState(
                        systemImage: "hammer",
                        title: "No instructions",
                        message: "Tell Magzi how to improve itself. It codes the change on a branch and asks you to approve."
                    )
                } else {
                    let open = list.filter { !$0.isTerminal }.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
                    let done = list.filter(\.isTerminal).sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
                    if !open.isEmpty {
                        MagziSectionHeader("In progress")
                        ForEach(open) { card($0) }
                    }
                    if !done.isEmpty {
                        MagziSectionHeader("Finished")
                        ForEach(done) { card($0) }
                    }
                }
            } else {
                ForEach(0..<3, id: \.self) { i in
                    card(MagziInstruction(id: "placeholder-\(i)", instruction: "Placeholder instruction describing a change", status: "coding", detail: "Placeholder detail"))
                }
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
            }
        }
        .task { if store.instructions == nil { await store.loadInstructions() } }
        .sheet(isPresented: $showComposer) {
            MagziOpsInstructionComposer(store: store)
        }
        .sheet(item: $approving) { inst in
            MagziOpsFieldSheet(
                title: "Approve",
                message: "Approving lets Magzi open a pull request for exactly this head commit. Check the branch before approving.",
                fieldLabel: "Head commit SHA",
                initialValue: inst.head ?? "",
                actionTitle: "Approve",
                error: store.sheetError
            ) { head in
                await store.act(inSheet: true) {
                    _ = try await store.api.approveAdminInstruction(id: inst.id, head: head)
                    await store.loadInstructions()
                }
            }
        }
        .sheet(item: $accepting) { inst in
            MagziOpsFieldSheet(
                title: "Accept",
                message: "Accept confirms the deployed change meets the acceptance criteria.",
                fieldLabel: "Commit",
                initialValue: inst.mergeCommit ?? inst.approvedHead ?? inst.head ?? "",
                actionTitle: "Accept",
                error: store.sheetError
            ) { commit in
                await store.act(inSheet: true) {
                    _ = try await store.api.acceptAdminInstruction(id: inst.id, commit: commit)
                    await store.loadInstructions()
                }
            }
        }
    }

    private func card(_ inst: MagziInstruction) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                MagziPill(title: MagziOpsFormat.humanize(inst.status), tint: Self.statusTint(inst.status))
                Spacer()
                Text(MagziOpsFormat.relative(ms: inst.updatedAt ?? inst.createdAt))
                    .font(MagziDesign.Typography.caption)
                    .foregroundStyle(MagziDesign.labelTertiary)
            }
            Text(inst.instruction ?? "–")
                .font(MagziDesign.Typography.body)
                .foregroundStyle(MagziDesign.label)
                .lineLimit(4)
            if let acceptance = inst.acceptance, !acceptance.isEmpty {
                Text("Acceptance: \(acceptance)")
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .lineLimit(3)
            }
            if let detail = inst.detail, !detail.isEmpty {
                Text(detail)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(inst.status == "failed" ? MagziDesign.rose : MagziDesign.labelSecondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            if let scope = inst.scope, !scope.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MagziDesign.Spacing.xs) {
                        ForEach(scope, id: \.self) { MagziPill(title: $0, systemImage: "folder", tint: MagziDesign.labelSecondary) }
                    }
                }
            }
            VStack(spacing: MagziDesign.Spacing.xs) {
                if let branch = inst.branch { MagziOpsKeyValue(label: "Branch", value: branch, mono: true) }
                if let head = inst.head { MagziOpsKeyValue(label: "Head", value: String(head.prefix(12)), mono: true) }
                if let pr = inst.pr { MagziOpsKeyValue(label: "PR", value: "#\(pr)", mono: true) }
                if let merge = inst.mergeCommit { MagziOpsKeyValue(label: "Merge", value: String(merge.prefix(12)), mono: true) }
            }
            if inst.awaitingApproval || inst.awaitingAcceptance {
                HStack(spacing: MagziDesign.Spacing.s) {
                    if inst.awaitingApproval {
                        Button("Approve") { store.sheetError = nil; approving = inst }
                            .buttonStyle(MagziCompactButtonStyle(prominent: true))
                    }
                    if inst.awaitingAcceptance {
                        Button("Accept") { store.sheetError = nil; accepting = inst }
                            .buttonStyle(MagziCompactButtonStyle(prominent: true))
                    }
                }
                .padding(.top, MagziDesign.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .magziCard()
    }

    static func statusTint(_ status: String?) -> Color {
        switch status {
        case "completed": return MagziDesign.mint
        case "failed": return MagziDesign.rose
        case "awaiting_approval", "awaiting_acceptance", "awaiting_setup", "awaiting_deploy", "queued": return MagziDesign.amber
        default: return MagziDesign.blue
        }
    }
}

/// Composer sheet: instruction, acceptance, scope tags, idempotency key.
private struct MagziOpsInstructionComposer: View {
    @ObservedObject var store: MagziOpsStore

    @State private var instruction = ""
    @State private var acceptance = ""
    @State private var scopeInput = ""
    @State private var scope: [String] = []
    /// Stable across retries so a resubmit after a timeout doesn't queue twice.
    @State private var idempotencyKey = UUID().uuidString
    @State private var isWorking = false
    @State private var validation: String?
    @Environment(\.dismiss) private var dismiss

    private static let pathCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-")

    private var canSubmit: Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !acceptance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !scope.isEmpty && scope.count <= 14 && !isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MagziDesign.Spacing.l) {
                    editor("Instruction", text: $instruction, placeholder: "Tell Magzi how to improve…", minHeight: 120)
                    editor("Acceptance", text: $acceptance, placeholder: "How you'll know it's done", minHeight: 80)

                    VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                        label("Scope (\(scope.count)/14)")
                        HStack(spacing: MagziDesign.Spacing.s) {
                            TextField("src/plugins/whatsapp", text: $scopeInput)
                                .font(MagziDesign.Typography.mono)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit(addScope)
                                .padding(.horizontal, MagziDesign.Spacing.m)
                                .frame(minHeight: 40)
                                .background(fieldBackground)
                            Button("Add", action: addScope)
                                .buttonStyle(MagziCompactButtonStyle())
                                .disabled(scopeInput.trimmingCharacters(in: .whitespaces).isEmpty || scope.count >= 14)
                        }
                        if !scope.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: MagziDesign.Spacing.xs) {
                                    ForEach(scope, id: \.self) { path in
                                        Button {
                                            scope.removeAll { $0 == path }
                                        } label: {
                                            MagziPill(title: path, systemImage: "xmark", tint: MagziDesign.labelSecondary)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove \(path)")
                                    }
                                }
                            }
                        }
                        Text("Relative paths Magzi may touch. Letters, digits, _ . / - only.")
                            .font(MagziDesign.Typography.footnote)
                            .foregroundStyle(MagziDesign.labelTertiary)
                    }

                    VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
                        label("Idempotency key")
                        HStack {
                            Text(idempotencyKey)
                                .font(MagziDesign.Typography.mono)
                                .foregroundStyle(MagziDesign.labelSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer()
                            Button("New") { idempotencyKey = UUID().uuidString }
                                .font(MagziDesign.Typography.footnote)
                                .foregroundStyle(MagziDesign.mint)
                        }
                    }

                    if let validation = validation ?? store.sheetError {
                        Text(validation)
                            .font(MagziDesign.Typography.footnote)
                            .foregroundStyle(MagziDesign.rose)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isWorking { ProgressView() } else { Text("Submit") }
                    }
                    .buttonStyle(MagziPrimaryButtonStyle())
                    .disabled(!canSubmit)
                }
                .padding(MagziDesign.Spacing.gutter)
            }
            .magziScreenBackground()
            .navigationTitle("New instruction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous)
            .fill(MagziDesign.surfaceSecondary)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(MagziDesign.Typography.eyebrow)
            .foregroundStyle(MagziDesign.labelTertiary)
    }

    private func editor(_ title: String, text: Binding<String>, placeholder: String, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            label(title)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(MagziDesign.Typography.body)
                        .foregroundStyle(MagziDesign.labelTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(MagziDesign.Typography.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
            }
            .padding(MagziDesign.Spacing.s)
            .background(fieldBackground)
        }
    }

    private func addScope() {
        let paths = scopeInput
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map(String.init)
        for path in paths {
            guard path.unicodeScalars.allSatisfy({ Self.pathCharacters.contains($0) }),
                  !path.hasPrefix("/"), !path.contains("..") else {
                validation = "“\(path)” isn't a valid relative path."
                return
            }
            if !scope.contains(path) && scope.count < 14 { scope.append(path) }
        }
        validation = nil
        scopeInput = ""
    }

    private func submit() async {
        validation = nil
        if !scopeInput.trimmingCharacters(in: .whitespaces).isEmpty { addScope() }
        guard validation == nil, canSubmit else { return }
        isWorking = true
        defer { isWorking = false }
        let ok = await store.act(inSheet: true) {
            _ = try await store.api.createAdminInstruction(
                instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                acceptance: acceptance.trimmingCharacters(in: .whitespacesAndNewlines),
                scope: scope,
                idempotencyKey: idempotencyKey
            )
            await store.loadInstructions()
        }
        if ok { dismiss() }
    }
}
