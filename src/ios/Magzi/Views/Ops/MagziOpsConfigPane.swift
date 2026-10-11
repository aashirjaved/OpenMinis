import SwiftUI

/// Config: WhatsApp allowlist + typed config keys with rollback.
struct MagziOpsConfigPane: View {
    @ObservedObject var store: MagziOpsStore

    @State private var newRecipient = ""
    @State private var pendingRemoval: String?
    @State private var editingKey: MagziOpsEditingKey?
    @State private var confirmRollback = false
    @State private var confirmRestart = false
    @State private var working = false

    var body: some View {
        MagziOpsPane(refresh: { await store.loadState() }) {
            if let error = store.stateError, store.state == nil {
                MagziOpsErrorCard(message: error, retry: { await store.loadState() })
            } else if let state = store.state {
                if let error = store.stateError {
                    MagziOpsErrorCard(message: error, retry: { await store.loadState() })
                }
                content(state)
            } else {
                content(MagziCockpitState(allowlist: ["+440000000000", "+440000000001"]))
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
            }
        }
        .task { if store.state == nil { await store.loadState() } }
        .sheet(item: $editingKey) { editing in
            MagziOpsConfigEditSheet(key: editing.key, currentValue: Self.currentValue(editing.key, in: store.state?.config), error: store.sheetError) { value in
                await save(editing.key, value)
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval ?? "")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { recipient in
            Button("Remove from allowlist", role: .destructive) { Task { await deny(recipient) } }
        } message: { _ in
            Text("Magzi will no longer send WhatsApp messages to this recipient.")
        }
        .confirmationDialog("Roll back the last config change?", isPresented: $confirmRollback, titleVisibility: .visible) {
            Button("Roll back", role: .destructive) { Task { await rollback() } }
        } message: {
            Text("Restores config.json to the version before this change. A restart is needed to apply it.")
        }
        .confirmationDialog("Restart magzid?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart service", role: .destructive) {
                Task { await store.act { _ = try await store.api.restart() } }
            }
        } message: {
            Text("Chats pause for about 20 seconds.")
        }
    }

    @ViewBuilder
    private func content(_ state: MagziCockpitState) -> some View {
        if let change = store.lastConfigChange {
            changeCard(change)
        }

        MagziSectionHeader("Config")
        VStack(spacing: 0) {
            ForEach(Array(MagziConfigKey.allCases.enumerated()), id: \.element) { index, key in
                if index > 0 { MagziOpsDivider() }
                Button {
                    store.sheetError = nil
                    editingKey = MagziOpsEditingKey(key: key)
                } label: {
                    HStack(spacing: MagziDesign.Spacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.magziOpsTitle)
                                .font(MagziDesign.Typography.body)
                                .foregroundStyle(MagziDesign.label)
                            Text(key.rawValue)
                                .font(MagziDesign.Typography.mono)
                                .foregroundStyle(MagziDesign.labelTertiary)
                        }
                        Spacer(minLength: MagziDesign.Spacing.s)
                        Text(Self.currentValue(key, in: state.config) ?? "Not set")
                            .font(MagziDesign.Typography.mono)
                            .foregroundStyle(MagziDesign.labelSecondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(.footnote, design: .default, weight: .semibold))
                            .foregroundStyle(MagziDesign.labelTertiary)
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .magziCard(padding: MagziDesign.Spacing.m)
        Text("Changes are written to config.json and take effect after a restart.")
            .font(MagziDesign.Typography.footnote)
            .foregroundStyle(MagziDesign.labelTertiary)
            .padding(.horizontal, MagziDesign.Spacing.xs)

        MagziSectionHeader("WhatsApp allowlist")
        allowlistCard(state)
    }

    // MARK: Allowlist

    private func allowlistCard(_ state: MagziCockpitState) -> some View {
        let list = state.allowlist ?? []
        return VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            HStack(spacing: MagziDesign.Spacing.s) {
                TextField("+44 7700 900000", text: $newRecipient)
                    .font(MagziDesign.Typography.mono)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .padding(.horizontal, MagziDesign.Spacing.m)
                    .frame(minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous)
                            .fill(MagziDesign.surfaceSecondary)
                    )
                Button("Add") { Task { await allow() } }
                    .buttonStyle(MagziCompactButtonStyle(prominent: true))
                    .disabled(newRecipient.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            if list.isEmpty {
                Text("No recipients yet. Magzi can only message people on this list proactively.")
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element) { index, recipient in
                        if index > 0 { MagziOpsDivider() }
                        HStack(spacing: MagziDesign.Spacing.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipient)
                                    .font(MagziDesign.Typography.mono)
                                    .foregroundStyle(MagziDesign.label)
                                    .textSelection(.enabled)
                                if let grant = state.allowlistGrants?[recipient]?.last {
                                    Text([grant.reason, MagziOpsFormat.relative(grant.grantedAt)].compactMap { $0 }.joined(separator: " · "))
                                        .font(MagziDesign.Typography.footnote)
                                        .foregroundStyle(MagziDesign.labelSecondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Button {
                                pendingRemoval = recipient
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(MagziDesign.rose)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(recipient)")
                        }
                    }
                }
            }
        }
        .magziCard()
    }

    // MARK: Change result

    private func changeCard(_ change: MagziOpsConfigChange) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            HStack(spacing: MagziDesign.Spacing.s) {
                MagziStatusDot(change.rolledBack ? .off : .attention)
                Text(change.rolledBack ? "Rolled back \(change.key.rawValue)" : "Saved \(change.key.rawValue)")
                    .font(MagziDesign.Typography.headline)
                    .foregroundStyle(MagziDesign.label)
                Spacer()
                Button {
                    store.lastConfigChange = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MagziDesign.labelTertiary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            if !change.rolledBack {
                MagziOpsKeyValue(label: "New value", value: change.value, mono: true)
            }
            if change.restartRequired {
                Text("Restart required for this to take effect.")
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.amber)
            }
            if let hash = change.rollbackHash, !change.rolledBack {
                MagziOpsKeyValue(label: "Rollback hash", value: hash, mono: true)
            }
            HStack(spacing: MagziDesign.Spacing.s) {
                if change.rollbackHash != nil && !change.rolledBack {
                    Button("Roll back") { confirmRollback = true }
                        .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.amber))
                }
                if change.restartRequired {
                    Button("Restart now") { confirmRestart = true }
                        .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.rose))
                }
            }
        }
        .magziCard()
    }

    // MARK: Actions

    private func allow() async {
        let recipient = newRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else { return }
        working = true
        defer { working = false }
        let ok = await store.act {
            let r = try await store.api.allow(recipient: recipient)
            if let list = r.allowlist { store.state?.allowlist = list }
        }
        if ok { newRecipient = "" }
    }

    private func deny(_ recipient: String) async {
        await store.act {
            let r = try await store.api.deny(recipient: recipient)
            if let list = r.allowlist {
                store.state?.allowlist = list
            } else {
                store.state?.allowlist?.removeAll { $0 == recipient }
            }
        }
    }

    private func save(_ key: MagziConfigKey, _ raw: String) async -> Bool {
        let value: Any
        if key.magziOpsIsInteger {
            guard let int = Int(raw) else {
                store.sheetError = "\(key.magziOpsTitle) must be a whole number."
                return false
            }
            value = int
        } else {
            value = raw
        }
        return await store.act(inSheet: true) {
            let r = try await store.api.setConfig(key, value: value)
            store.lastConfigChange = MagziOpsConfigChange(
                key: key, value: raw, restartRequired: r.restartRequired ?? true, rollbackHash: r.rollbackHash
            )
            await store.loadState()
        }
    }

    private func rollback() async {
        guard let change = store.lastConfigChange, let hash = change.rollbackHash else { return }
        await store.act {
            let r = try await store.api.rollbackConfig(expectedHash: hash)
            var updated = change
            updated.rolledBack = true
            updated.restartRequired = r.restartRequired ?? true
            store.lastConfigChange = updated
            await store.loadState()
        }
    }

    /// Reads a dotted key (`backups.retentionDays`) out of the raw config JSON.
    static func currentValue(_ key: MagziConfigKey, in config: JSONValue?) -> String? {
        var node = config
        for part in key.rawValue.split(separator: ".") {
            node = node?[String(part)]
        }
        guard let node, !node.isNull else { return nil }
        return node.stringValue ?? MagziOpsFormat.compact(node)
    }
}

private struct MagziOpsEditingKey: Identifiable {
    let key: MagziConfigKey
    var id: String { key.rawValue }
}

extension MagziConfigKey {
    var magziOpsTitle: String {
        switch self {
        case .timezone: return "Timezone"
        case .agentProfile: return "Agent profile"
        case .turnConcurrency: return "Turn concurrency"
        case .updateCheckIntervalHours: return "Update check interval"
        case .backupsRetentionDays: return "Backup retention"
        }
    }

    var magziOpsHint: String {
        switch self {
        case .timezone: return "An IANA zone, e.g. Europe/London."
        case .agentProfile: return "personal, family, front-desk or coworker."
        case .turnConcurrency: return "Parallel turns, 1–16."
        case .updateCheckIntervalHours: return "Hours between update checks, 1–168."
        case .backupsRetentionDays: return "Days to keep backups, 1–365."
        }
    }

    var magziOpsIsInteger: Bool {
        switch self {
        case .turnConcurrency, .updateCheckIntervalHours, .backupsRetentionDays: return true
        case .timezone, .agentProfile: return false
        }
    }

    var magziOpsSuggestions: [String] {
        switch self {
        case .agentProfile: return ["personal", "family", "front-desk", "coworker"]
        case .timezone: return [TimeZone.current.identifier, "Europe/London", "UTC"]
        default: return []
        }
    }
}

/// Edit sheet for one config key.
private struct MagziOpsConfigEditSheet: View {
    let key: MagziConfigKey
    let currentValue: String?
    let error: String?
    let save: (String) async -> Bool

    @State private var value: String
    @State private var isWorking = false
    @Environment(\.dismiss) private var dismiss

    init(key: MagziConfigKey, currentValue: String?, error: String?, save: @escaping (String) async -> Bool) {
        self.key = key
        self.error = error
        self.currentValue = currentValue
        self.save = save
        _value = State(initialValue: currentValue ?? "")
    }

    private var trimmed: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MagziDesign.Spacing.l) {
                    VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
                        Text(key.rawValue)
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                            .foregroundStyle(MagziDesign.label)
                        Text(key.magziOpsHint)
                            .font(MagziDesign.Typography.footnote)
                            .foregroundStyle(MagziDesign.labelSecondary)
                        if let currentValue {
                            Text("Current: \(currentValue)")
                                .font(MagziDesign.Typography.mono)
                                .foregroundStyle(MagziDesign.labelTertiary)
                        }
                    }
                    TextField("Value", text: $value)
                        .font(MagziDesign.Typography.mono)
                        .keyboardType(key.magziOpsIsInteger ? .numberPad : .default)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(MagziDesign.Spacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous)
                                .fill(MagziDesign.surfaceSecondary)
                        )
                    if !key.magziOpsSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: MagziDesign.Spacing.s) {
                                ForEach(Array(Set(key.magziOpsSuggestions)).sorted(), id: \.self) { suggestion in
                                    Button(suggestion) { value = suggestion }
                                        .buttonStyle(MagziCompactButtonStyle(tint: value == suggestion ? MagziDesign.mint : MagziDesign.labelSecondary))
                                }
                            }
                        }
                    }
                    if let error {
                        Text(error)
                            .font(MagziDesign.Typography.footnote)
                            .foregroundStyle(MagziDesign.rose)
                    }
                    Text("Saving requires a restart. You can roll back right after.")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelTertiary)
                    Button {
                        Task {
                            isWorking = true
                            let ok = await save(trimmed)
                            isWorking = false
                            if ok { dismiss() }
                        }
                    } label: {
                        if isWorking { ProgressView() } else { Text("Save") }
                    }
                    .buttonStyle(MagziPrimaryButtonStyle())
                    .disabled(trimmed.isEmpty || trimmed == currentValue || isWorking)
                }
                .padding(MagziDesign.Spacing.gutter)
            }
            .magziScreenBackground()
            .navigationTitle(key.magziOpsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
