import SwiftUI

/// Household group chat (WhatsApp group mirror). Server returns newest-first; `MagziAPI.thread`
/// already reverses to oldest → newest for a chat-like list.
struct HhThreadView: View {
    let householdId: String

    private struct Pending: Identifiable, Hashable {
        let id: String
        let text: String
        var failed: Bool = false
    }

    @State private var lines: [MagziThreadLine]?
    @State private var pending: [Pending] = []
    @State private var error: String?
    @State private var sendError: String?
    @State private var draft = ""
    @State private var loadingOlder = false
    @State private var reachedStart = false
    @FocusState private var composerFocused: Bool

    private let bottomId = "hh-thread-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                    Text("This is your family WhatsApp group. Messages you send here post to the group.")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, MagziDesign.Spacing.s)
                    if let error, lines == nil {
                        HhErrorCard(message: error) { Task { await load() } }
                    } else if let lines {
                        if lines.isEmpty && pending.isEmpty {
                            MagziEmptyState(systemImage: "bubble.left.and.bubble.right", title: "No messages yet", message: "Say something to the household.")
                                .frame(maxWidth: .infinity)
                        } else if !reachedStart && lines.count >= 50 {
                            Button {
                                Task { await loadOlder() }
                            } label: {
                                if loadingOlder { ProgressView() } else { Text("Load earlier messages") }
                            }
                            .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.labelSecondary))
                            .frame(maxWidth: .infinity)
                        }
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            bubble(line, showsSpeaker: index == 0 || lines[index - 1].speaker != line.speaker)
                                .id(line.id)
                        }
                        ForEach(pending) { p in pendingBubble(p) }
                    } else {
                        ForEach(0..<6, id: \.self) { i in
                            HStack {
                                if i % 2 == 0 { Spacer() }
                                Text("Placeholder message text here")
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: MagziDesign.Radius.bubble).fill(MagziDesign.surface))
                                if i % 2 == 1 { Spacer() }
                            }
                        }
                        .redacted(reason: .placeholder)
                    }
                    Color.clear.frame(height: 1).id(bottomId)
                }
                .padding(.horizontal, MagziDesign.Spacing.l)
                .padding(.bottom, MagziDesign.Spacing.s)
            }
            .scrollDismissesKeyboard(.interactively)
            .magziScreenBackground()
            .refreshable { await load() }
            .safeAreaInset(edge: .bottom) { composer }
            .onChange(of: lines?.last?.id) { _ in
                withAnimation(MagziDesign.Motion.standard) { proxy.scrollTo(bottomId, anchor: .bottom) }
            }
            .onChange(of: pending.count) { _ in
                withAnimation(MagziDesign.Motion.standard) { proxy.scrollTo(bottomId, anchor: .bottom) }
            }
            .task {
                await load()
                proxy.scrollTo(bottomId, anchor: .bottom)
            }
        }
        .navigationTitle("Group chat")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(MagziHub.shared.threadLines.receive(on: DispatchQueue.main)) { event in
            guard event.householdId == householdId else { return }
            append(event.line)
        }
    }

    // MARK: Bubbles

    private var speakers: [String] {
        var names: [String] = []
        for s in (lines ?? []).compactMap(\.speaker) where !names.contains(s) { names.append(s) }
        return names
    }

    private func isOwn(_ line: MagziThreadLine) -> Bool {
        line.fromMagzi != true && HhIdentity.isMe(line.speaker)
    }

    private func bubble(_ line: MagziThreadLine, showsSpeaker: Bool) -> some View {
        let own = isOwn(line)
        let magzi = line.fromMagzi == true
        return HStack(alignment: .bottom) {
            if own { Spacer(minLength: 48) }
            VStack(alignment: own ? .trailing : .leading, spacing: 3) {
                if showsSpeaker && !own {
                    HStack(spacing: 4) {
                        if magzi { Image(systemName: "sparkle").font(.caption2) }
                        Text(magzi ? "Magzi" : (line.speaker ?? "Someone"))
                    }
                    .font(MagziDesign.Typography.caption)
                    .foregroundStyle(magzi ? MagziDesign.mint : HhPalette.color(for: line.speaker ?? "", in: speakers))
                }
                Text(line.text ?? "")
                    .font(MagziDesign.Typography.body)
                    .foregroundStyle(own ? MagziDesign.onAccent : MagziDesign.label)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: MagziDesign.Radius.bubble, style: .continuous)
                            .fill(own ? MagziDesign.mint : magzi ? MagziDesign.mintSoft : MagziDesign.surface)
                    )
                HStack(spacing: 4) {
                    if line.channel == "app" {
                        Image(systemName: "iphone").font(.caption2)
                    }
                    Text(HhFormat.time(line.at))
                }
                .font(MagziDesign.Typography.caption)
                .foregroundStyle(MagziDesign.labelTertiary)
            }
            if !own { Spacer(minLength: 48) }
        }
        .padding(.top, showsSpeaker ? MagziDesign.Spacing.s : 0)
        .accessibilityElement(children: .combine)
    }

    private func pendingBubble(_ p: Pending) -> some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 3) {
                Text(p.text)
                    .font(MagziDesign.Typography.body)
                    .foregroundStyle(MagziDesign.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: MagziDesign.Radius.bubble, style: .continuous)
                            .fill(MagziDesign.mint.opacity(p.failed ? 0.4 : 0.7))
                    )
                if p.failed {
                    HStack(spacing: 8) {
                        Text("Not sent").foregroundStyle(MagziDesign.rose)
                        Button("Retry") { Task { await send(p.text, clientMessageId: p.id) } }
                            .foregroundStyle(MagziDesign.mint)
                    }
                    .font(MagziDesign.Typography.caption)
                } else {
                    Label("Sending", systemImage: "clock")
                        .font(MagziDesign.Typography.caption)
                        .foregroundStyle(MagziDesign.labelTertiary)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let sendError {
                Text(sendError)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.rose)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: MagziDesign.Spacing.s) {
                TextField("Message the group", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: MagziDesign.Radius.bubble, style: .continuous)
                            .fill(MagziDesign.surfaceSecondary)
                    )
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    draft = ""
                    Task { await send(text, clientMessageId: UUID().uuidString) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MagziDesign.labelTertiary : MagziDesign.mint)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, MagziDesign.Spacing.l)
        .padding(.vertical, MagziDesign.Spacing.s)
        .background(MagziDesign.background.opacity(0.98).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: Data

    private func append(_ line: MagziThreadLine) {
        guard lines?.contains(where: { $0.id == line.id }) == false else { return }
        withAnimation(MagziDesign.Motion.standard) {
            lines?.append(line)
            if let text = line.text, let i = pending.firstIndex(where: { !$0.failed && text.contains($0.text) }) {
                pending.remove(at: i)
            }
        }
    }

    private func load() async {
        do {
            let fresh = try await MagziAPI.shared.thread(householdId: householdId)
            withAnimation(MagziDesign.Motion.standard) {
                if var existing = lines, let firstFresh = fresh.first {
                    // Keep older pages already loaded.
                    existing.removeAll { $0.id >= firstFresh.id }
                    lines = existing + fresh
                } else {
                    lines = fresh
                }
                pending.removeAll { p in !p.failed && fresh.contains { ($0.text ?? "").contains(p.text) } }
            }
            error = nil
        } catch {
            if HhErrors.isCancellation(error) { return }
            self.error = HhErrors.message(error)
        }
    }

    private func loadOlder() async {
        guard let first = lines?.first, !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let older = try await MagziAPI.shared.thread(householdId: householdId, before: first.id)
            if older.isEmpty { reachedStart = true }
            let known = Set((lines ?? []).map(\.id))
            lines = older.filter { !known.contains($0.id) } + (lines ?? [])
            if older.count < 50 { reachedStart = true }
        } catch {
            sendError = HhErrors.message(error)
        }
    }

    private func send(_ text: String, clientMessageId: String) async {
        HhHaptics.light()
        sendError = nil
        if let i = pending.firstIndex(where: { $0.id == clientMessageId }) {
            pending[i].failed = false
        } else {
            pending.append(Pending(id: clientMessageId, text: text))
        }
        do {
            try await MagziAPI.shared.postThread(householdId: householdId, text: text, clientMessageId: clientMessageId)
            // The socket usually delivers the line; refetch as a fallback.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if pending.contains(where: { $0.id == clientMessageId }) { await load() }
            // If the server line never matched our text, stop showing it as pending.
            if pending.contains(where: { $0.id == clientMessageId }) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await load()
                pending.removeAll { $0.id == clientMessageId }
            }
        } catch {
            HhHaptics.error()
            if let i = pending.firstIndex(where: { $0.id == clientMessageId }) { pending[i].failed = true }
            sendError = HhErrors.message(error)
        }
    }
}
