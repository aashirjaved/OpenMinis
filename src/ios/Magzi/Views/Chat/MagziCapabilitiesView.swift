import SwiftUI
import UIKit

/// One starter prompt on the Capabilities launcher.
struct MagziSkillTile: Identifiable, Hashable {
    enum Tint: Hashable { case mint, blue, amber, rose, violet, neutral }

    let title: String
    let systemImage: String
    let tint: Tint
    /// Prompts ending in a fragment ("Remind me to") are intentional: the user finishes the sentence.
    let prompt: String

    var id: String { title }

    var color: Color {
        switch tint {
        case .mint: return MagziDesign.mint
        case .blue: return MagziDesign.blue
        case .amber: return MagziDesign.amber
        case .rose: return MagziDesign.rose
        case .violet: return MagziDesign.violet
        case .neutral: return MagziDesign.labelSecondary
        }
    }

    /// Fragments are prefilled for the user to finish; complete questions can run straight away.
    var isFragment: Bool {
        guard let last = prompt.trimmingCharacters(in: .whitespaces).last else { return true }
        return !".?!".contains(last)
    }
}

struct MagziSkillSection: Identifiable, Hashable {
    let title: String
    let tiles: [MagziSkillTile]
    var id: String { title }
}

struct MagziCapabilityCatalog {
    static let sections: [MagziSkillSection] = [
        MagziSkillSection(title: "Money & markets", tiles: [
            MagziSkillTile(title: "Portfolio", systemImage: "chart.line.uptrend.xyaxis", tint: .mint,
                           prompt: "Give me a quick portfolio check: total value, today's move, and anything unusual."),
            MagziSkillTile(title: "Crypto wallet", systemImage: "bitcoinsign.circle", tint: .amber,
                           prompt: "What's in my crypto wallet right now, and how has it changed this week?"),
            MagziSkillTile(title: "Trader desk", systemImage: "bell.badge", tint: .rose,
                           prompt: "Show my active trader desk alerts and anything that triggered in the last 24 hours."),
            MagziSkillTile(title: "Markets", systemImage: "globe", tint: .blue,
                           prompt: "Give me your current market world-view in five bullets, with the news driving it."),
        ]),
        MagziSkillSection(title: "Home & family", tiles: [
            MagziSkillTile(title: "Agenda", systemImage: "calendar", tint: .blue,
                           prompt: "What's on my agenda today? Include calendar events, reminders, chores and anything due."),
            MagziSkillTile(title: "Reminders", systemImage: "bell", tint: .amber, prompt: "Remind me to "),
            MagziSkillTile(title: "Tasks & goals", systemImage: "target", tint: .mint,
                           prompt: "Show my open tasks and goals, and suggest the one thing I should do next."),
            MagziSkillTile(title: "Home Assistant", systemImage: "lightbulb", tint: .amber,
                           prompt: "What's the state of the house right now? Lights, heating, doors."),
        ]),
        MagziSkillSection(title: "Media & creative", tiles: [
            MagziSkillTile(title: "Instagram studio", systemImage: "camera", tint: .rose, prompt: "Draft an Instagram post about "),
            MagziSkillTile(title: "Image", systemImage: "photo", tint: .violet, prompt: "Make an image of "),
            MagziSkillTile(title: "Read aloud", systemImage: "speaker.wave.2", tint: .neutral, prompt: "Read this aloud for me: "),
            MagziSkillTile(title: "Media request", systemImage: "film", tint: .violet, prompt: "Add this to Magziflex: "),
        ]),
        MagziSkillSection(title: "Work & Google", tiles: [
            MagziSkillTile(title: "Gmail", systemImage: "envelope", tint: .rose,
                           prompt: "Summarise my unread email. Flag anything that needs a reply today."),
            MagziSkillTile(title: "Calendar", systemImage: "calendar.badge.plus", tint: .blue,
                           prompt: "Find a free hour this week and hold it for "),
            MagziSkillTile(title: "Drive", systemImage: "folder", tint: .blue, prompt: "Find the document in my Drive about "),
        ]),
        MagziSkillSection(title: "Automation & skills", tiles: [
            MagziSkillTile(title: "Automations", systemImage: "clock.arrow.2.circlepath", tint: .mint,
                           prompt: "List my scheduled automations with their next run, and tell me if any failed recently."),
            MagziSkillTile(title: "New automation", systemImage: "plus.circle", tint: .mint, prompt: "Every weekday at 8am, "),
            MagziSkillTile(title: "Browser task", systemImage: "safari", tint: .blue, prompt: "Go to this website and "),
            MagziSkillTile(title: "Skills", systemImage: "wand.and.stars", tint: .violet,
                           prompt: "What skills have you learned recently, and did any of them need fixing?"),
        ]),
        MagziSkillSection(title: "Life tools", tiles: [
            MagziSkillTile(title: "Weather", systemImage: "cloud.sun", tint: .blue,
                           prompt: "What's the weather today and tomorrow where I am? Anything I should plan around?"),
            MagziSkillTile(title: "Directions", systemImage: "map", tint: .blue, prompt: "How long will it take to get to "),
            MagziSkillTile(title: "Research", systemImage: "magnifyingglass", tint: .violet,
                           prompt: "Research this for me and come back with a short brief and sources: "),
            MagziSkillTile(title: "News brief", systemImage: "newspaper", tint: .neutral,
                           prompt: "Brief me on the news that matters to me today. Keep it under two minutes to read."),
            MagziSkillTile(title: "Recall", systemImage: "brain", tint: .violet, prompt: "What do you remember about "),
        ]),
        MagziSkillSection(title: "Homelab", tiles: [
            MagziSkillTile(title: "Nextcloud", systemImage: "externaldrive", tint: .blue, prompt: "Find in Nextcloud: "),
            MagziSkillTile(title: "Homecloud", systemImage: "server.rack", tint: .neutral,
                           prompt: "Which homecloud services are running, and is anything unhealthy?"),
        ]),
    ]

    static let all: [MagziSkillTile] = sections.flatMap(\.tiles)

    static func tile(titled title: String) -> MagziSkillTile? { all.first { $0.title == title } }

    /// Sections filtered by a search query (title or prompt), empty sections dropped.
    static func sections(matching query: String) -> [MagziSkillSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sections }
        return sections.compactMap { section in
            let sectionMatches = section.title.localizedCaseInsensitiveContains(q)
            let tiles = sectionMatches ? section.tiles : section.tiles.filter {
                $0.title.localizedCaseInsensitiveContains(q) || $0.prompt.localizedCaseInsensitiveContains(q)
            }
            return tiles.isEmpty ? nil : MagziSkillSection(title: section.title, tiles: tiles)
        }
    }
}

/// Launcher of starter prompts. Pushed from More/Home — the caller supplies the NavigationStack.
struct MagziCapabilitiesView: View {
    @ObservedObject private var router = MagziRouter.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var copiedTitle: String?

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: MagziDesign.Spacing.m, alignment: .top), count: count)
    }

    private var sections: [MagziSkillSection] { MagziCapabilityCatalog.sections(matching: query) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MagziDesign.Spacing.section) {
                Text("Things Magzi can do. Tap one to start a conversation.")
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .padding(.horizontal, MagziDesign.Spacing.xs)

                if sections.isEmpty {
                    MagziEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No matches",
                        message: "Nothing matches \u{201C}\(query)\u{201D}. You can still ask Magzi directly.",
                        actionTitle: "Ask Magzi",
                        action: { ask(query, send: false) }
                    )
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
                            MagziSectionHeader(section.title)
                            LazyVGrid(columns: columns, spacing: MagziDesign.Spacing.m) {
                                ForEach(section.tiles) { tile in
                                    tileButton(tile)
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, MagziDesign.Spacing.gutter)
            .padding(.top, MagziDesign.Spacing.s)
            .padding(.bottom, MagziDesign.Spacing.xxxl)
            .animation(reduceMotion ? nil : MagziDesign.Motion.standard, value: sections.map(\.id))
        }
        .magziScreenBackground()
        .navigationTitle("Capabilities")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search capabilities")
        .overlay(alignment: .bottom) {
            if let copiedTitle {
                MagziCapabilityToast(text: "Copied \u{201C}\(copiedTitle)\u{201D} prompt")
                    .padding(.bottom, MagziDesign.Spacing.l)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func tileButton(_ tile: MagziSkillTile) -> some View {
        Button {
            ask(tile.prompt, send: false)
        } label: {
            MagziSkillTileView(tile: tile)
        }
        .buttonStyle(MagziTilePressStyle())
        .contextMenu {
            if !tile.isFragment {
                Button {
                    ask(tile.prompt, send: true)
                } label: {
                    Label("Ask now", systemImage: "paperplane")
                }
            }
            Button {
                ask(tile.prompt, send: false)
            } label: {
                Label("Open in chat", systemImage: "bubble.left")
            }
            Button {
                runAdhoc(tile.prompt)
            } label: {
                Label("Run as ad-hoc task with 9router", systemImage: "bolt.horizontal")
            }
            Button {
                copy(tile)
            } label: {
                Label("Copy prompt", systemImage: "doc.on.doc")
            }
        }
        .accessibilityHint(tile.isFragment ? "Starts a message for you to finish" : "Opens Magzi chat with this question")
    }

    private func ask(_ prompt: String, send: Bool) {
        let trimmed = prompt.trimmingCharacters(in: .newlines)
        guard !trimmed.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        router.askMagzi(trimmed, send: send)
    }

    private func runAdhoc(_ prompt: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        router.tab = .adhoc
        let name = Notification.Name.magziAdhocNewTask
        // Give the ad-hoc tab a beat to mount its observer before posting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: name, object: prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func copy(_ tile: MagziSkillTile) {
        UIPasteboard.general.string = tile.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(reduceMotion ? nil : MagziDesign.Motion.standard) { copiedTitle = tile.title }
        let title = tile.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard copiedTitle == title else { return }
            withAnimation(reduceMotion ? nil : MagziDesign.Motion.standard) { copiedTitle = nil }
        }
    }
}

private struct MagziSkillTileView: View {
    let tile: MagziSkillTile

    var body: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            MagziIconBadge(systemImage: tile.systemImage, tint: tile.color, size: 36)
            Spacer(minLength: 0)
            Text(tile.title)
                .font(MagziDesign.Typography.footnote.weight(.medium))
                .foregroundStyle(MagziDesign.label)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .magziCard(padding: 12)
        .contentShape(RoundedRectangle(cornerRadius: MagziDesign.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tile.title)
    }
}

private struct MagziTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(MagziDesign.Motion.quick, value: configuration.isPressed)
    }
}

private struct MagziCapabilityToast: View {
    let text: String

    var body: some View {
        HStack(spacing: MagziDesign.Spacing.s) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(MagziDesign.mint)
            Text(text)
                .font(MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.label)
                .lineLimit(1)
        }
        .padding(.horizontal, MagziDesign.Spacing.l)
        .padding(.vertical, MagziDesign.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MagziDesign.surfaceElevated)
        )
        .magziShadow(MagziDesign.Shadows.floating)
        .accessibilityElement(children: .combine)
    }
}
