import SwiftUI
import UIKit

/// Root of the Magzi tab: the one-to-one conversation with Magzi (app thread or unified person thread).
struct MagziChatView: View {
    @ObservedObject private var store = MagziChatStore.shared
    @ObservedObject private var hub = MagziHub.shared
    @ObservedObject private var socket = MagziWebSocket.shared
    @ObservedObject private var auth = MagziAuthStore.shared
    @ObservedObject private var router = MagziRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @State private var showConnect = false
    @State private var showCapabilities = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var lastFailedCount = 0

    private var isOffline: Bool {
        if case .offline = hub.status { return true }
        return false
    }

    /// Sending is plain HTTP; when the socket is down the store polls history for the reply.
    private var canSend: Bool { auth.isPaired }

    var body: some View {
        NavigationStack {
            content
                .magziScreenBackground()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .navigationDestination(isPresented: $showCapabilities) { MagziCapabilitiesView() }
        }
        .sheet(isPresented: $showConnect) { MagziConnectView() }
        .onAppear {
            consumeDraft()
            consumeDictationRequest()
            if auth.isPaired {
                socket.connect()
                if store.messages.isEmpty { Task { await store.reload() } }
            }
            lastFailedCount = failedCount
        }
        .onChange(of: router.chatDraft) { _ in consumeDraft() }
        .onChange(of: router.startDictation) { _ in consumeDictationRequest() }
        .onChange(of: failedCount) { newValue in
            if newValue > lastFailedCount { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            lastFailedCount = newValue
        }
        .onChange(of: auth.isPaired) { paired in if paired { showConnect = false } }
    }

    private var failedCount: Int { store.messages.filter(\.isFailed).count }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !auth.isPaired {
            ScrollView {
                MagziEmptyState(
                    systemImage: "link",
                    title: "Not connected",
                    message: "Connect to your home server to chat with Magzi.",
                    actionTitle: "Connect",
                    action: { showConnect = true }
                )
                .padding(.horizontal, MagziDesign.Spacing.gutter)
                .padding(.top, MagziDesign.Spacing.xxxl)
            }
        } else {
            VStack(spacing: 0) {
                banners
                MagziChatMessageList(
                    store: store,
                    searchText: isSearching ? searchText : "",
                    showsChannels: store.useUnifiedThread && store.canUseUnifiedThread,
                    onSuggestion: { send($0) }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MagziChatComposer(
                    text: $draft,
                    focused: $composerFocused,
                    isEnabled: canSend,
                    placeholder: isOffline ? "Message Magzi · offline" : "Message Magzi",
                    onSend: { send(draft) },
                    onCapabilities: { showCapabilities = true }
                )
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 0) {
            if isSearching {
                MagziChatSearchField(text: $searchText) {
                    withAnimation(animation) {
                        isSearching = false
                        searchText = ""
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if isOffline {
                MagziChatBanner(systemImage: "wifi.slash", tint: MagziDesign.labelSecondary,
                                text: "Offline \u{2014} Magzi will be back shortly.",
                                actionTitle: "Retry") { socket.reconnect() }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if hub.isAdmin, hub.pendingApprovalsCount > 0 {
                MagziChatBanner(
                    systemImage: "checkmark.shield",
                    tint: MagziDesign.amber,
                    text: hub.pendingApprovalsCount == 1
                        ? "1 approval needs your OK"
                        : "\(hub.pendingApprovalsCount) approvals need your OK",
                    actionTitle: "Review"
                ) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    router.showHouseholdApprovals = true
                    router.tab = .household
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(animation, value: isOffline)
        .animation(animation, value: hub.pendingApprovalsCount)
    }

    private var animation: Animation? { reduceMotion ? nil : MagziDesign.Motion.standard }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text("Magzi")
                    .font(MagziDesign.Typography.headline)
                    .foregroundStyle(MagziDesign.label)
                HStack(spacing: 5) {
                    MagziStatusDot(dotStatus, size: 6)
                    Text(statusLine)
                        .font(MagziDesign.Typography.caption)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Magzi, \(statusLine)")
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if auth.isPaired {
                Button {
                    withAnimation(animation) {
                        isSearching.toggle()
                        if !isSearching { searchText = "" }
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search conversation")

                Menu {
                    Toggle(isOn: $store.useUnifiedThread) {
                        Label("Unified thread (app + WhatsApp)", systemImage: "bubble.left.and.bubble.right")
                    }
                    .disabled(!store.canUseUnifiedThread)
                    Button {
                        showCapabilities = true
                    } label: {
                        Label("Capabilities", systemImage: "square.grid.2x2")
                    }
                    Button {
                        Task { await store.reload() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    if !draft.isEmpty {
                        Button(role: .destructive) {
                            draft = ""
                        } label: {
                            Label("Clear draft", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
    }

    private var dotStatus: MagziStatus {
        switch hub.status {
        case .online: return socket.isConnected ? .live : .ok
        case .connecting: return .attention
        case .offline, .unpaired: return .off
        }
    }

    private var statusLine: String {
        let base: String
        switch hub.status {
        case .unpaired: base = "Not connected"
        case .connecting: base = "Connecting\u{2026}"
        case .offline: base = "Offline"
        case .online: base = store.isTyping ? "Typing\u{2026}" : "Online"
        }
        if store.useUnifiedThread && store.canUseUnifiedThread, hub.status != .unpaired {
            return base + " \u{00B7} App + WhatsApp"
        }
        return base
    }

    // MARK: Actions

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSend else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if text == draft { draft = "" }
        Task { await store.send(trimmed) }
    }

    /// Home's mic button: focus the composer so the keyboard's dictation key is one tap away.
    /// (SpeechRecognitionManager is wired to the ad-hoc chat's voice panel and has no stop
    /// affordance in this composer, so we rely on system dictation here.)
    private func consumeDictationRequest() {
        guard router.startDictation else { return }
        router.startDictation = false
        guard canSend else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { composerFocused = true }
    }

    private func consumeDraft() {
        guard let prompt = router.chatDraft else { return }
        let sendNow = router.sendDraftImmediately
        router.chatDraft = nil
        router.sendDraftImmediately = false
        if sendNow, canSend, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            send(prompt)
        } else {
            draft = prompt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { composerFocused = true }
        }
    }
}

// MARK: - Message list

private enum MagziChatRow: Identifiable {
    case day(Date)
    case message(MagziChatMessage, first: Bool, last: Bool, time: Date?)

    var id: String {
        switch self {
        case .day(let date): return "day:\(Int(date.timeIntervalSince1970))"
        case .message(let m, _, _, _): return m.id
        }
    }
}

private struct MagziChatMessageList: View {
    @ObservedObject var store: MagziChatStore
    let searchText: String
    let showsChannels: Bool
    let onSuggestion: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isNearBottom = true
    @State private var hasUnseen = false
    @State private var didInitialScroll = false

    private static let bottomId = "magzi.chat.bottom"
    private static let space = "magzi.chat.scroll"

    private var visibleMessages: [MagziChatMessage] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.messages }
        return store.messages.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    private var showsTypingRow: Bool {
        store.isTyping && !store.messages.contains(where: \.isStreaming)
    }

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        header
                        rowsView(width: outer.size.width)
                        if showsTypingRow && searchText.isEmpty {
                            MagziChatTypingIndicator()
                                .padding(.top, MagziDesign.Spacing.l)
                                .transition(.opacity)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomId)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: MagziChatBottomOffsetKey.self,
                                        value: geo.frame(in: .named(Self.space)).maxY
                                    )
                                }
                            )
                    }
                    .padding(.horizontal, MagziDesign.Spacing.l)
                    .padding(.top, MagziDesign.Spacing.s)
                    .padding(.bottom, MagziDesign.Spacing.m)
                    .animation(reduceMotion ? nil : MagziDesign.Motion.standard, value: store.messages.map(\.id))
                    .animation(reduceMotion ? nil : MagziDesign.Motion.standard, value: showsTypingRow)
                }
                .coordinateSpace(name: Self.space)
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    if store.hasMoreHistory { await store.loadOlder() } else { await store.reload() }
                }
                .onPreferenceChange(MagziChatBottomOffsetKey.self) { maxY in
                    let near = maxY - outer.size.height < 80
                    if near != isNearBottom { isNearBottom = near }
                    if near { hasUnseen = false }
                }
                .onChange(of: store.messages.last?.id) { _ in follow(proxy, isNewItem: true) }
                .onChange(of: store.streamingText) { _ in follow(proxy, isNewItem: false) }
                .onChange(of: showsTypingRow) { _ in follow(proxy, isNewItem: false) }
                .onChange(of: store.messages.isEmpty) { empty in
                    if !empty, !didInitialScroll { initialScroll(proxy) }
                }
                .onAppear { initialScroll(proxy) }
                .overlay(alignment: .bottomTrailing) {
                    if !isNearBottom && !store.messages.isEmpty {
                        MagziChatJumpButton(hasUnseen: hasUnseen) {
                            hasUnseen = false
                            withAnimation(reduceMotion ? nil : MagziDesign.Motion.standard) {
                                proxy.scrollTo(Self.bottomId, anchor: .bottom)
                            }
                        }
                        .padding(.trailing, MagziDesign.Spacing.l)
                        .padding(.bottom, MagziDesign.Spacing.m)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(reduceMotion ? nil : MagziDesign.Motion.standard, value: isNearBottom)
            }
        }
    }

    private func initialScroll(_ proxy: ScrollViewProxy) {
        guard !store.messages.isEmpty else { return }
        didInitialScroll = true
        DispatchQueue.main.async { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
    }

    private func follow(_ proxy: ScrollViewProxy, isNewItem: Bool) {
        // Follow my own message and the reply to it, even if the keyboard moved the
        // viewport so "near bottom" reads false.
        let msgs = store.messages
        let lastIsMine = msgs.last?.role == .user
        let replyToMine = msgs.count >= 2 && msgs[msgs.count - 2].role == .user
        // A line Magzi started itself (a brief, an approval outcome) is why
        // you're looking at this tab: show it.
        let proactive = isNewItem && msgs.last?.isProactive == true
        if isNearBottom || lastIsMine || replyToMine || proactive || store.isTyping {
            if isNewItem && !reduceMotion {
                withAnimation(MagziDesign.Motion.standard) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
            } else {
                proxy.scrollTo(Self.bottomId, anchor: .bottom)
            }
        } else {
            hasUnseen = true
        }
    }

    // MARK: Header (load older / states)

    @ViewBuilder
    private var header: some View {
        if store.isLoadingOlder {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, MagziDesign.Spacing.m)
        } else if store.hasMoreHistory && searchText.isEmpty {
            Button {
                Task { await store.loadOlder() }
            } label: {
                Text("Load earlier messages")
                    .font(MagziDesign.Typography.footnote.weight(.medium))
                    .foregroundStyle(MagziDesign.mint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MagziDesign.Spacing.m)
            }
            .buttonStyle(.plain)
        }

        if let error = store.error {
            MagziChatErrorCard(message: error, onRetry: {
                Task { await store.reload() }
            }, onDismiss: {
                store.error = nil
            })
            .padding(.vertical, MagziDesign.Spacing.s)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if store.messages.isEmpty {
            if store.isLoading {
                MagziChatSkeleton()
            } else if store.error == nil {
                VStack(spacing: MagziDesign.Spacing.l) {
                    MagziEmptyState(
                        systemImage: "sparkle",
                        title: "Say hi to Magzi",
                        message: "Magzi knows your household, remembers what matters and can act for you."
                    )
                    MagziChatSuggestions(onTap: onSuggestion)
                }
                .padding(.top, MagziDesign.Spacing.xl)
            }
        } else if !searchText.isEmpty && visibleMessages.isEmpty {
            MagziEmptyState(systemImage: "magnifyingglass", title: "No matches",
                            message: "Nothing in this conversation matches \u{201C}\(searchText)\u{201D}.")
        }
    }

    // MARK: Rows

    private func rowsView(width: CGFloat) -> some View {
        ForEach(Self.rows(for: visibleMessages)) { row in
            switch row {
            case .day(let date):
                Text(Self.dayLabel(date))
                    .font(MagziDesign.Typography.caption)
                    .foregroundStyle(MagziDesign.labelTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .accessibilityAddTraits(.isHeader)
            case .message(let message, let first, let last, let time):
                MagziChatMessageRow(
                    message: message,
                    isFirstInGroup: first,
                    isLastInGroup: last,
                    groupTime: time,
                    isLastUserMessage: message.id == lastUserMessageId,
                    showsChannel: showsChannels,
                    maxBubbleWidth: max(120, (width - MagziDesign.Spacing.l * 2) * 0.78),
                    onRetry: { Task { await store.retry(message.id) } },
                    onDiscard: { store.discardFailed(message.id) },
                    onAction: onSuggestion
                )
                .padding(.top, first ? MagziDesign.Spacing.l : MagziDesign.Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var lastUserMessageId: String? { store.messages.last(where: { $0.role == .user })?.id }

    private static func rows(for messages: [MagziChatMessage]) -> [MagziChatRow] {
        var rows: [MagziChatRow] = []
        let calendar = Calendar.current
        let groupGap: TimeInterval = 3 * 60
        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let newDay = previous.map { !calendar.isDate($0.createdAt, inSameDayAs: message.createdAt) } ?? true
            if newDay { rows.append(.day(message.createdAt)) }
            let first = newDay || previous.map { !sameGroup($0, message, gap: groupGap) } ?? true
            let nextSameDay = next.map { calendar.isDate($0.createdAt, inSameDayAs: message.createdAt) } ?? false
            let last = next.map { !(nextSameDay && sameGroup(message, $0, gap: groupGap)) } ?? true
            var time: Date?
            if last, !message.isStreaming {
                // Only when the next group starts more than 10 minutes later (or there is none — then it's the latest).
                if let next {
                    if next.createdAt.timeIntervalSince(message.createdAt) > 10 * 60 { time = message.createdAt }
                } else if Date().timeIntervalSince(message.createdAt) > 10 * 60 {
                    time = message.createdAt
                }
            }
            rows.append(.message(message, first: first, last: last, time: time))
        }
        return rows
    }

    private static func sameGroup(_ a: MagziChatMessage, _ b: MagziChatMessage, gap: TimeInterval) -> Bool {
        a.role == b.role && !a.isProactive && !b.isProactive && abs(b.createdAt.timeIntervalSince(a.createdAt)) <= gap
            && (a.channel ?? "app") == (b.channel ?? "app")
    }

    private static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.isDate(date, equalTo: Date(), toGranularity: .year) ? "EEE d MMM" : "EEE d MMM yyyy"
        )
        return formatter.string(from: date)
    }
}

private struct MagziChatBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Message row

private struct MagziChatMessageRow: View {
    let message: MagziChatMessage
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    let groupTime: Date?
    let isLastUserMessage: Bool
    let showsChannel: Bool
    let maxBubbleWidth: CGFloat
    let onRetry: () -> Void
    let onDiscard: () -> Void
    let onAction: (String) -> Void

    @State private var confirmFailed = false

    private var channelBadge: (title: String, symbol: String)? {
        guard showsChannel, isFirstInGroup, let channel = message.channel?.lowercased(), channel != "app" else { return nil }
        switch channel {
        case "whatsapp": return ("WhatsApp", "message")
        case "telegram": return ("Telegram", "paperplane")
        case "email": return ("Email", "envelope")
        case "ipad": return ("iPad", "ipad")
        case "mac": return ("Mac", "laptopcomputer")
        default: return (channel.capitalized, "bubble.left")
        }
    }

    var body: some View {
        Group {
            if message.role == .user {
                userRow
            } else if message.isProactive {
                MagziChatProactiveCard(message: message, onAction: onAction)
                    .contextMenu { contextItems }
            } else {
                assistantRow
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    // User

    private var userRow: some View {
        VStack(alignment: .trailing, spacing: MagziDesign.Spacing.xs) {
            Text(message.text)
                .font(MagziDesign.Typography.body)
                .foregroundStyle(MagziDesign.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(bubbleShape(isTail: isLastInGroup).fill(MagziDesign.mintSoft))
                .overlay(
                    bubbleShape(isTail: isLastInGroup)
                        .stroke(message.isFailed ? MagziDesign.rose.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .opacity(message.status == .pending ? 0.7 : 1)
                .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
                .contentShape(bubbleShape(isTail: isLastInGroup))
                .onTapGesture { if message.isFailed { confirmFailed = true } }
                .contextMenu { contextItems }
                .accessibilityLabel("You said: \(message.text)")

            if let badge = channelBadge {
                MagziPill(title: badge.title, systemImage: badge.symbol, tint: MagziDesign.labelSecondary)
            }
            deliveryState
            timeLabel
        }
        .confirmationDialog("Message not sent", isPresented: $confirmFailed, titleVisibility: .visible) {
            Button("Try again", action: onRetry)
            Button("Discard", role: .destructive, action: onDiscard)
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var deliveryState: some View {
        if message.isFailed {
            Button { confirmFailed = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                    Text("Not sent \u{00B7} Tap to retry")
                }
                .font(magziChatCaption2)
                .foregroundStyle(MagziDesign.rose)
            }
            .buttonStyle(.plain)
        } else if message.status == .pending && isLastUserMessage {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text("Sending\u{2026}")
            }
            .font(magziChatCaption2)
            .foregroundStyle(MagziDesign.labelTertiary)
            .transition(.opacity)
        }
    }

    // Assistant

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isFirstInGroup {
                HStack(spacing: 6) {
                    MagziChatAvatar()
                    Text("Magzi")
                        .font(MagziDesign.Typography.caption.weight(.semibold))
                        .foregroundStyle(MagziDesign.labelSecondary)
                    if let badge = channelBadge {
                        MagziPill(title: badge.title, systemImage: badge.symbol, tint: MagziDesign.labelSecondary)
                    }
                }
                .accessibilityHidden(true)
            }
            MagziChatMarkdownText(text: message.text, showsStreamingDot: message.isStreaming)
                .contextMenu { contextItems }
                .accessibilityLabel("Magzi said: \(message.text)")
            timeLabel
        }
    }

    @ViewBuilder
    private var timeLabel: some View {
        if let groupTime {
            Text(groupTime, style: .time)
                .font(magziChatCaption2)
                .foregroundStyle(MagziDesign.labelTertiary)
        }
    }

    // Context menu

    @ViewBuilder
    private var contextItems: some View {
        Text(contextHeader)
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        if message.isFailed {
            Button(action: onRetry) { Label("Try again", systemImage: "arrow.clockwise") }
            Button(role: .destructive, action: onDiscard) { Label("Discard", systemImage: "trash") }
        }
    }

    private var contextHeader: String {
        let time = message.createdAt.formatted(date: .abbreviated, time: .shortened)
        let channel: String
        switch message.channel?.lowercased() {
        case "whatsapp": channel = "WhatsApp"
        case nil, "app": channel = "App"
        case let other?: channel = other.capitalized
        }
        return "\(time) \u{00B7} \(channel)"
    }
}

/// Rounded bubble with a tighter bottom-trailing corner on the last message of a group.
private func bubbleShape(isTail: Bool) -> AnyShape {
    if isTail, #available(iOS 17, *) {
        return AnyShape(UnevenRoundedRectangle(
            topLeadingRadius: MagziDesign.Radius.bubble,
            bottomLeadingRadius: MagziDesign.Radius.bubble,
            bottomTrailingRadius: 6,
            topTrailingRadius: MagziDesign.Radius.bubble,
            style: .continuous
        ))
    }
    return AnyShape(RoundedRectangle(cornerRadius: MagziDesign.Radius.bubble, style: .continuous))
}

private struct MagziChatAvatar: View {
    var body: some View {
        Image("MagziLogo")
            .resizable()
            .scaledToFill()
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Proactive card

private struct MagziChatProactiveCard: View {
    let message: MagziChatMessage
    let onAction: (String) -> Void

    private var eyebrow: String {
        let kind = (message.meta?["kind"]?.stringValue ?? message.meta?["source"]?.stringValue ?? "").lowercased()
        if kind.contains("brief") { return kind.contains("evening") ? "EVENING BRIEF" : "MORNING BRIEF" }
        if kind.contains("check") { return "CHECK-IN" }
        if kind.contains("nudge") || kind.contains("heads") || kind.contains("alert") || kind.contains("poke") {
            return "HEADS UP"
        }
        return "FROM MAGZI"
    }

    private var actions: [(title: String, prompt: String)] {
        guard case .array(let items)? = message.meta?["actions"] else { return [] }
        return items.prefix(3).compactMap { item in
            if let s = item.stringValue { return (s, s) }
            guard let title = item["title"]?.stringValue ?? item["label"]?.stringValue else { return nil }
            return (title, item["prompt"]?.stringValue ?? item["text"]?.stringValue ?? title)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(MagziDesign.mint)
                Text(eyebrow)
                    .font(MagziDesign.Typography.eyebrow)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .tracking(0.6)
                Spacer(minLength: MagziDesign.Spacing.s)
                Text(message.createdAt, style: .time)
                    .font(magziChatCaption2)
                    .foregroundStyle(MagziDesign.labelTertiary)
            }
            MagziChatMarkdownText(text: message.text)
            if !actions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MagziDesign.Spacing.s) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                            Button(action.title) { onAction(action.prompt) }
                                .buttonStyle(MagziCompactButtonStyle(prominent: index == 0))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .magziCard(padding: 14)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Streaming / typing

private struct MagziChatTypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            MagziChatAvatar()
            if reduceMotion {
                dots(phase: nil)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    dots(phase: t.truncatingRemainder(dividingBy: 1.2) / 1.2)
                }
            }
        }
        .padding(.vertical, MagziDesign.Spacing.xs)
        .accessibilityElement()
        .accessibilityLabel("Magzi is typing")
    }

    private func dots(phase: Double?) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(MagziDesign.labelTertiary)
                    .frame(width: 6, height: 6)
                    .opacity(opacity(for: i, phase: phase))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(MagziDesign.surfaceSecondary))
    }

    private func opacity(for index: Int, phase: Double?) -> Double {
        guard let phase else { return 0.5 }
        // Each dot peaks a third of a cycle after the previous one.
        let local = (phase - Double(index) / 3).truncatingRemainder(dividingBy: 1)
        let p = local < 0 ? local + 1 : local
        let wave = p < 0.5 ? p * 2 : (1 - p) * 2
        return 0.3 + 0.7 * wave
    }
}

private struct MagziChatJumpButton: View {
    let hasUnseen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(MagziDesign.label)
                .frame(width: 36, height: 36)
                .background(Circle().fill(MagziDesign.surfaceElevated))
                .overlay(Circle().stroke(MagziDesign.hairline, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if hasUnseen {
                        Circle().fill(MagziDesign.mint).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(MagziDesign.surfaceElevated, lineWidth: 2))
                    }
                }
                .magziShadow(MagziDesign.Shadows.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasUnseen ? "Scroll to new messages" : "Scroll to bottom")
    }
}

// MARK: - States

private struct MagziChatSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.l) {
            ForEach(0..<4, id: \.self) { i in
                if i.isMultiple(of: 2) {
                    Text("Placeholder message from you")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(MagziDesign.mintSoft))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text("A longer placeholder reply from Magzi that spans a couple of lines of text in the list.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(MagziDesign.Typography.body)
        .redacted(reason: .placeholder)
        .padding(.top, MagziDesign.Spacing.l)
        .accessibilityLabel("Loading conversation")
    }
}

private struct MagziChatErrorCard: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(MagziDesign.rose)
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                Text("Couldn\u{2019}t load the conversation")
                    .font(MagziDesign.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(MagziDesign.label)
                Text(message)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .lineLimit(3)
                Button("Try again", action: onRetry)
                    .buttonStyle(MagziCompactButtonStyle())
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(MagziDesign.labelTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .magziCard(padding: 14)
    }
}

private struct MagziChatSuggestions: View {
    let onTap: (String) -> Void
    private let prompts = ["What's on today?", "Add milk to the list", "How's the week going?"]

    var body: some View {
        VStack(spacing: MagziDesign.Spacing.s) {
            ForEach(prompts, id: \.self) { prompt in
                Button { onTap(prompt) } label: {
                    Text(prompt)
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.label)
                        .padding(.horizontal, MagziDesign.Spacing.l)
                        .padding(.vertical, 10)
                        .background(Capsule(style: .continuous).fill(MagziDesign.surfaceSecondary))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MagziChatBanner: View {
    let systemImage: String
    let tint: Color
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: MagziDesign.Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(MagziDesign.Typography.footnote)
                .foregroundStyle(MagziDesign.label)
                .lineLimit(2)
            Spacer(minLength: MagziDesign.Spacing.s)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(MagziDesign.Typography.footnote.weight(.semibold))
                    .foregroundStyle(tint == MagziDesign.labelSecondary ? MagziDesign.mint : tint)
            }
        }
        .padding(.horizontal, MagziDesign.Spacing.l)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(MagziDesign.surfaceSecondary)
        .overlay(alignment: .bottom) { MagziDesign.hairline.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .accessibilityElement(children: .combine)
    }
}

private struct MagziChatSearchField: View {
    @Binding var text: String
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: MagziDesign.Spacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(MagziDesign.labelTertiary)
                TextField("Search this conversation", text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
            }
            .font(MagziDesign.Typography.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous)
                .fill(MagziDesign.surfaceSecondary))
            Button("Done", action: onClose)
                .font(MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.mint)
        }
        .padding(.horizontal, MagziDesign.Spacing.l)
        .padding(.vertical, MagziDesign.Spacing.s)
        .background(MagziDesign.surface)
        .overlay(alignment: .bottom) { MagziDesign.hairline.frame(height: 1) }
        .onAppear { focused = true }
    }
}

// MARK: - Composer

private struct MagziChatComposer: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let isEnabled: Bool
    let placeholder: String
    let onSend: () -> Void
    let onCapabilities: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: MagziDesign.Spacing.s) {
            Menu {
                Button(action: onCapabilities) {
                    Label("Capabilities", systemImage: "square.grid.2x2")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("More options")

            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...6)
                .font(MagziDesign.Typography.body)
                .focused(focused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(MagziDesign.surfaceSecondary))
                .disabled(!isEnabled)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(.subheadline, design: .default, weight: .bold))
                    .foregroundStyle(hasText && isEnabled ? MagziDesign.onAccent : MagziDesign.labelTertiary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(hasText && isEnabled ? MagziDesign.mint : MagziDesign.surfaceSecondary))
                    .scaleEffect(hasText ? 1 : 0.92)
            }
            .buttonStyle(.plain)
            .disabled(!hasText || !isEnabled)
            .padding(.bottom, 2)
            .accessibilityLabel("Send")
            .animation(reduceMotion ? nil : MagziDesign.Motion.standard, value: hasText)
        }
        .padding(.horizontal, MagziDesign.Spacing.m)
        .padding(.vertical, MagziDesign.Spacing.s)
        .background(MagziDesign.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { MagziDesign.hairline.frame(height: 1) }
    }
}

private let magziChatCaption2 = Font.system(.caption2)
