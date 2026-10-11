import SwiftUI

/// Ops cockpit (spec §4.9). Pushed from More — relies on the caller's NavigationStack.
struct MagziOpsView: View {
    static let sessionEndedCopy = "Session ended (Magzi restarted). Sign in again."

    @ObservedObject private var auth = MagziCockpitAuth.shared
    @StateObject private var store = MagziOpsStore()
    @StateObject private var live = MagziOpsLiveFeed()

    @State private var section: MagziOpsSection = .overview
    @State private var notice: String?
    @State private var userSignedOut = false
    @State private var confirmSignOut = false

    var body: some View {
        Group {
            if auth.isLoggedIn {
                cockpit
            } else {
                MagziOpsLoginScreen(notice: notice)
            }
        }
        .magziScreenBackground()
        .navigationTitle("Ops")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: auth.isLoggedIn) { loggedIn in
            if loggedIn {
                notice = nil
                userSignedOut = false
                store.sessionEnded = false
            } else {
                if !userSignedOut { notice = Self.sessionEndedCopy }
                store.reset()
                live.reset()
            }
        }
        .onChange(of: store.sessionEnded) { ended in
            guard ended else { return }
            notice = Self.sessionEndedCopy
            if auth.isLoggedIn { auth.signOut() }
        }
        .alert("Action failed", isPresented: Binding(
            get: { store.actionError != nil },
            set: { if !$0 { store.actionError = nil } }
        )) {
            Button("OK", role: .cancel) { store.actionError = nil }
        } message: {
            Text(store.actionError ?? "")
        }
    }

    private var cockpit: some View {
        VStack(spacing: 0) {
            MagziOpsSectionBar(selection: $section)
            Group {
                switch section {
                case .overview: MagziOpsOverviewPane(store: store)
                case .capabilities: MagziOpsCapabilitiesPane(store: store)
                case .usage: MagziOpsUsagePane(store: store)
                case .sessions: MagziOpsSessionsPane(store: store)
                case .live: MagziOpsLivePane(store: store, feed: live)
                case .config: MagziOpsConfigPane(store: store)
                case .improve: MagziOpsImprovePane(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        confirmSignOut = true
                    } label: {
                        Label("Sign out of Ops", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Ops options")
                }
            }
        }
        .confirmationDialog("Sign out of the Ops cockpit?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                userSignedOut = true
                Task { await auth.logout() }
            }
        } message: {
            Text("You'll need a new code from WhatsApp to get back in.")
        }
    }
}

/// Styled wrapper around the core `MagziCockpitLoginView` (spec: centred card like Connect).
private struct MagziOpsLoginScreen: View {
    let notice: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: MagziDesign.Spacing.m) {
                MagziIconBadge(systemImage: "gauge.with.dots.needle.33percent", size: 56)
                Text("Ops cockpit")
                    .font(MagziDesign.Typography.title)
                    .foregroundStyle(MagziDesign.label)
                Text("We'll send a one-time code to the owner's WhatsApp.")
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .multilineTextAlignment(.center)
                if let notice {
                    HStack(spacing: MagziDesign.Spacing.s) {
                        MagziStatusDot(.attention)
                        Text(notice)
                            .font(MagziDesign.Typography.footnote)
                            .foregroundStyle(MagziDesign.label)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, MagziDesign.Spacing.m)
                    .padding(.vertical, MagziDesign.Spacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous)
                            .fill(MagziDesign.amber.opacity(0.12))
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MagziDesign.Spacing.gutter)
            .padding(.top, MagziDesign.Spacing.xl)
            .padding(.bottom, MagziDesign.Spacing.s)

            MagziCockpitLoginView()
                .scrollContentBackground(.hidden)
                .tint(MagziDesign.mint)
        }
        .background(MagziDesign.background.ignoresSafeArea())
    }
}
