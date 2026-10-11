import SwiftUI
import UIKit

/// The household 9router gateway that powers Ad-hoc tasks. Mirrors the ids seeded by
/// `ProviderConfigStore.ensureLocalDefaultProviderIfConfigured()`.
enum MagziGateway {
    static let instanceId = "local-default-9router"
    static let groupId = "local-default-9router-group"

    @MainActor static var instance: ProviderInstance? { ProviderConfigStore.shared.instance(for: instanceId) }

    /// `{customBaseURL}` (+ `/v1` when the instance asks for it), no trailing slash.
    @MainActor static var baseURLString: String? {
        guard let inst = instance, var base = inst.customBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty else {
            return nil
        }
        while base.hasSuffix("/") { base.removeLast() }
        if inst.appendV1Suffix, !base.hasSuffix("/v1") { base += "/v1" }
        return base
    }

    static func entryId(_ modelId: String) -> String { "\(instanceId)/\(modelId)" }

    /// Model ids in the 9router group, default first.
    @MainActor static var groupModelIds: [String] {
        let prefix = instanceId + "/"
        let members = ProviderConfigStore.shared.group(for: groupId)?.memberEntryIds ?? []
        return members.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    @MainActor static var defaultModelId: String? { groupModelIds.first }

    @MainActor static var routesNewTasks: Bool { ProviderConfigStore.shared.defaultPrimaryGroupId == groupId }

    /// `GET {base}/models` with the instance key (OpenAI list format). The key is never logged.
    @MainActor static func fetchModelIds() async throws -> [String] {
        guard let base = baseURLString, let url = URL(string: base + "/models") else { throw MagziError.notConfigured }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = ProviderKeychainHelper.loadAPIKey(instanceId: instanceId), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw MagziError.http(status, status == 401 || status == 403 ? "The gateway rejected the key." : "The gateway answered \(status).")
        }
        struct ModelList: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]?
            let models: [Model]?
        }
        let list = try JSONDecoder().decode(ModelList.self, from: data)
        let ids = (list.data ?? list.models ?? []).map(\.id).filter { !$0.isEmpty }
        return Array(Set(ids)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Adds entries for `modelIds`, makes them the 9router group's members (default first), and keeps
    /// that group the default for new sessions so every Ad-hoc task runs through 9router.
    @MainActor static func apply(modelIds: [String], defaultId: String) {
        let store = ProviderConfigStore.shared
        let ordered = [defaultId] + modelIds.filter { $0 != defaultId }
        for id in ordered where store.entry(for: entryId(id)) == nil {
            store.addEntry(ModelEntry(
                providerInstanceId: instanceId,
                model: LLMModel(id: id, displayName: id, provider: ProviderType.openAI.displayName),
                isCustom: true
            ))
        }
        let members = ordered.map(entryId)
        let label = instance?.label ?? "9router"
        if var group = store.group(for: groupId) {
            if group.memberEntryIds != members {
                group.memberEntryIds = members
                store.updateGroup(group)
            }
        } else {
            store.addGroup(ModelGroup(
                id: groupId,
                name: label,
                memberEntryIds: members,
                strategy: .fallback,
                fallbackStrategy: .always,
                defaultThinkingLevel: .high
            ))
        }
        if store.defaultPrimaryGroupId != groupId { store.defaultPrimaryGroupId = groupId }
        for member in members { store.addAgentLoopEntry(member) }
        store.addAgentLoopGroup(groupId)
    }
}

/// Settings section: gateway URL, default model, and links into the model picker and provider screens.
struct MagziGatewaySection: View {
    @ObservedObject private var store = ProviderConfigStore.shared

    var body: some View {
        Section {
            if let base = MagziGateway.baseURLString {
                LabeledContent("Gateway") {
                    Text(base)
                        .font(MagziDesign.Typography.mono)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                LabeledContent("Default model", value: MagziGateway.defaultModelId ?? "None")
                NavigationLink {
                    MagziGatewayModelsView()
                } label: {
                    LabeledContent("Models", value: "\(MagziGateway.groupModelIds.count) on")
                }
                if !MagziGateway.routesNewTasks {
                    Button("Use 9router for new tasks") {
                        if let id = MagziGateway.defaultModelId {
                            MagziGateway.apply(modelIds: MagziGateway.groupModelIds, defaultId: id)
                        } else {
                            store.defaultPrimaryGroupId = MagziGateway.groupId
                        }
                    }
                }
            } else {
                Text("No 9router gateway is configured in this build. Add an OpenAI-compatible provider below.")
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
            }
            NavigationLink("Manage providers") { ProviderInstancesView() }
            NavigationLink("Model groups") { ModelGroupsView() }
            Button("All Ad-hoc settings") { ShellAdhocSettings.open(.home) }
        } header: {
            Text("Ad-hoc AI gateway")
        } footer: {
            Text(MagziGateway.routesNewTasks
                 ? "Every new Ad-hoc task runs on this iPhone through your household 9router gateway."
                 : "New Ad-hoc tasks currently use another default model group.")
        }
    }
}

/// Live model list from the gateway: choose which models are on and which is the default.
struct MagziGatewayModelsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var available: [String] = []
    @State private var enabled: Set<String> = []
    @State private var defaultId: String?
    @State private var query = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var loaded = false

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let all = available
        guard !q.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    private var canSave: Bool {
        guard let defaultId else { return false }
        return enabled.contains(defaultId) && (enabled != Set(MagziGateway.groupModelIds) || defaultId != MagziGateway.defaultModelId)
    }

    var body: some View {
        List {
            if let loadError {
                Section {
                    ShellErrorCard(message: loadError) { Task { await load() } }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            if let defaultId {
                Section("Default") {
                    Text(defaultId).font(MagziDesign.Typography.mono)
                }
            }
            Section {
                if isLoading && available.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in
                        Text("provider/model-name-placeholder").redacted(reason: .placeholder)
                    }
                } else if available.isEmpty && loaded && loadError == nil {
                    MagziEmptyState(systemImage: "cpu", title: "No models", message: "The gateway didn't list any models.")
                } else {
                    ForEach(filtered, id: \.self) { id in
                        row(id)
                    }
                }
            } header: {
                Text("Available on 9router")
            } footer: {
                Text("Turn on the models new tasks may use. Tap the star to make one the default; the others are fallbacks in order.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search models")
        .refreshable { await load() }
        .task { if !loaded { await load() } }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!canSave)
            }
        }
    }

    private func row(_ id: String) -> some View {
        let isOn = enabled.contains(id)
        let isDefault = defaultId == id
        return HStack(spacing: MagziDesign.Spacing.m) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                enabled.insert(id)
                defaultId = id
            } label: {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundStyle(isDefault ? MagziDesign.amber : MagziDesign.labelTertiary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDefault ? "Default model" : "Make default")

            Toggle(isOn: Binding(
                get: { isOn },
                set: { on in
                    if on { enabled.insert(id) } else {
                        enabled.remove(id)
                        if defaultId == id { defaultId = enabled.sorted().first }
                    }
                    if defaultId == nil, on { defaultId = id }
                }
            )) {
                Text(id)
                    .font(MagziDesign.Typography.mono)
                    .foregroundStyle(MagziDesign.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .tint(MagziDesign.mint)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false; loaded = true }
        let current = MagziGateway.groupModelIds
        if enabled.isEmpty { enabled = Set(current) }
        if defaultId == nil { defaultId = current.first }
        do {
            let ids = try await MagziGateway.fetchModelIds()
            // Keep configured models visible even if the gateway stopped listing them.
            available = ids + current.filter { !ids.contains($0) }
            loadError = nil
        } catch {
            if available.isEmpty { available = current }
            loadError = "Couldn't reach the 9router gateway. Check you're on the home network or Tailscale."
        }
    }

    private func save() {
        guard let defaultId, enabled.contains(defaultId) else { return }
        let order = available.filter { enabled.contains($0) }
        MagziGateway.apply(modelIds: order, defaultId: defaultId)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Opens the existing Ad-hoc (ContentView) settings sheet at a target.
@MainActor
enum ShellAdhocSettings {
    static func open(_ target: SettingsDeepLinkTarget) {
        MagziRouter.shared.tab = .adhoc
        let coordinator = DeepLinkCoordinator.shared
        coordinator.pendingSettingsTarget = nil
        // ContentView reacts to changes only; give a never-shown Ad-hoc tab a beat to mount.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            coordinator.pendingSettingsTarget = target
        }
    }
}
