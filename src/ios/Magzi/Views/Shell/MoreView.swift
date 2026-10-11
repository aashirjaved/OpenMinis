import SwiftUI

/// More tab: Me, Capabilities, Ad-hoc models, Admin/Ops (admins), Settings, About.
struct MoreView: View {
    @ObservedObject private var hub = MagziHub.shared
    @ObservedObject private var auth = MagziAuthStore.shared
    @ObservedObject private var adminHealth = MagziShellAdminHealth.shared
    @State private var showConnect = false

    var body: some View {
        List {
            if auth.isPaired {
                Section {
                    NavigationLink { MagziMeView() } label: { profileRow }
                }
                Section {
                    NavigationLink { MagziCapabilitiesView().navigationTitle("Capabilities") } label: {
                        MagziRow(title: "Capabilities", systemImage: "square.grid.2x2", tint: MagziDesign.mint)
                    }
                    adhocModelsLink
                }
                if hub.isAdmin {
                    Section {
                        NavigationLink { MagziAdminView() } label: {
                            MagziRow(title: "Admin", systemImage: "shield.lefthalf.filled", tint: MagziDesign.amber) {
                                if let status = adminHealth.status { MagziStatusDot(status) }
                            }
                        }
                        NavigationLink { MagziOpsView() } label: {
                            MagziRow(title: "Ops cockpit", systemImage: "gauge.with.dots.needle.33percent", tint: MagziDesign.labelSecondary)
                        }
                    }
                }
            } else {
                Section {
                    Button { showConnect = true } label: {
                        MagziRow(title: "Connect to Magzi", subtitle: "Sign in to your household server", systemImage: "house", tint: MagziDesign.mint, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    adhocModelsLink
                }
            }
            Section {
                NavigationLink { MagziSettingsView() } label: {
                    MagziRow(title: "Settings", systemImage: "gearshape", tint: MagziDesign.labelSecondary)
                }
                NavigationLink { AboutView() } label: {
                    MagziRow(title: "About", systemImage: "info.circle", tint: MagziDesign.labelSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await hub.refresh()
            await adminHealth.refreshIfAdmin()
        }
        .task { await adminHealth.refreshIfAdmin() }
        .onChange(of: auth.isPaired) { paired in if paired { showConnect = false } }
        .sheet(isPresented: $showConnect) {
            NavigationStack {
                MagziConnectView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { showConnect = false } }
                    }
            }
        }
    }

    @ViewBuilder private var adhocModelsLink: some View {
        if !hub.isMinor { // no on-device agent for a child or teen
            NavigationLink { MagziGatewayModelsView() } label: {
                MagziRow(title: "Ad-hoc models", subtitle: MagziGateway.defaultModelId, systemImage: "cpu", tint: MagziDesign.violet)
            }
        }
    }

    private var profileRow: some View {
        HStack(spacing: MagziDesign.Spacing.m) {
            Text(String((hub.user?.name ?? "M").prefix(1)).uppercased())
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(MagziDesign.label)
                .frame(width: 52, height: 52)
                .background(Circle().fill(MagziDesign.surfaceSecondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(hub.person?.displayName ?? hub.user?.name ?? "Me")
                    .font(MagziDesign.Typography.headline)
                    .foregroundStyle(MagziDesign.label)
                if let email = hub.user?.email, !email.isEmpty {
                    Text(email)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: MagziDesign.Spacing.s)
            if let role = hub.user?.role, !role.isEmpty {
                MagziPill(title: role.capitalized, tint: hub.isAdmin ? MagziDesign.amber : MagziDesign.labelSecondary)
            }
        }
        .padding(.vertical, MagziDesign.Spacing.xs)
        .redacted(reason: hub.user == nil ? .placeholder : [])
    }
}
