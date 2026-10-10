import SwiftUI
import Protocol

/// The phone's SMS, laid out like Messages on the Mac: conversations in a
/// list on the left, the selected one on the right with its bubbles, time
/// headers between bursts and a capsule field to reply.
struct MessagesView: View {
    let smsService: SmsService
    let connectionService: ConnectionService

    @State private var selectedId: SmsConversationMeta.ID?
    @State private var searchText = ""
    @State private var messageText = ""
    /// The oldest message on screen when an older page was asked for; the
    /// view is brought back to it once that page is in.
    @State private var olderPageAnchor: SmsMessageMeta.ID?
    /// The conversation is scrolled to within reach of its top.
    @State private var nearTop = false
    /// The top was reached while another load was in flight; that ask waits for it.
    @State private var olderPagePending = false

    private var selectedConversation: SmsConversationMeta? {
        smsService.conversations.first { $0.id == selectedId }
    }

    var body: some View {
        Group {
            if !connectionService.isConnected {
                ContentUnavailableView {
                    Label(L10n.isPL ? "Brak połączenia" : "Not Connected", systemImage: "wifi.slash")
                } description: {
                    Text(L10n.isPL ? "Połącz się z telefonem, aby przeglądać wiadomości." : "Connect to your phone to browse messages.")
                }
            } else {
                // Fixed list width: a split view sized itself to the selected
                // conversation, and long bubbles pushed the list narrower.
                HStack(spacing: 0) {
                    conversationList
                        .frame(width: 320)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .searchable(text: $searchText, placement: .toolbar,
                            prompt: L10n.isPL ? "Szukaj w wiadomościach" : "Search messages")
            }
        }
        .navigationTitle(selectedConversation?.displayName ?? (L10n.isPL ? "Wiadomości" : "Messages"))
        .toolbar {
            // The one place that says the phone is sending something. The
            // item stays in place and only fades: added and removed, it
            // re-laid the whole toolbar, and the window shook with every page.
            ToolbarItem(placement: .primaryAction) {
                ProgressView()
                    .controlSize(.small)
                    .opacity(smsService.isLoadingConversations || smsService.isLoadingMessages ? 1 : 0)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .navigationSubtitle(subtitle)
        .onAppear {
            if connectionService.isConnected && smsService.conversations.isEmpty {
                smsService.loadConversations()
            }
        }
        .onChange(of: connectionService.isConnected) { _, connected in
            if connected && smsService.conversations.isEmpty { smsService.loadConversations() }
        }
        .onChange(of: connectionService.activeDeviceId) { _, _ in
            // Switched phones — the selected conversation belonged to the
            // previous device; drop it and reload from the new one.
            selectedId = nil
            if connectionService.isConnected { smsService.loadConversations() }
        }
        .onChange(of: selectedId) { _, id in
            messageText = ""
            olderPageAnchor = nil
            nearTop = false
            olderPagePending = false
            if let convo = smsService.conversations.first(where: { $0.id == id }) {
                smsService.loadMessages(threadId: convo.threadId)
            }
        }
    }

    /// The number under the name, when the name is a contact's.
    private var subtitle: String {
        guard let convo = selectedConversation, convo.displayName != convo.address else { return "" }
        return convo.address
    }

    // MARK: - Conversations

    private var searchQuery: String { searchText.trimmingCharacters(in: .whitespaces) }

    private var filteredConversations: [SmsConversationMeta] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return smsService.conversations }
        return smsService.conversations.filter {
            SearchHighlight.matches($0.displayName, query)
                || SearchHighlight.matches($0.address, query)
                || SearchHighlight.matches($0.snippet, query)
        }
    }

    @ViewBuilder
    private var conversationList: some View {
        if smsService.isLoadingConversations && smsService.conversations.isEmpty {
            // Plain background; the toolbar spinner says it is loading.
            Color.clear
        } else if smsService.conversationsLoadFailed && smsService.conversations.isEmpty {
            ContentUnavailableView {
                Label(L10n.isPL ? "Nie udało się załadować" : "Could Not Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(L10n.isPL ? "Telefon nie odpowiedział. Spróbuj ponownie." : "The phone did not respond. Please try again.")
            } actions: {
                Button(L10n.isPL ? "Spróbuj ponownie" : "Try Again") { smsService.loadConversations() }
            }
        } else {
            List(filteredConversations, selection: $selectedId) { convo in
                ConversationRow(conversation: convo, isSelected: convo.id == selectedId, query: searchQuery)
                    .onAppear {
                        if convo.id == smsService.conversations.last?.id { smsService.loadMoreConversations() }
                    }
            }
            .listStyle(.inset)
            .overlay {
                if !searchText.isEmpty && filteredConversations.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    // MARK: - Conversation

    @ViewBuilder
    private var detail: some View {
        if let convo = selectedConversation {
            conversationView(convo)
        } else {
            ContentUnavailableView(L10n.isPL ? "Wybierz rozmowę" : "Select a Conversation",
                                   systemImage: "message",
                                   description: Text(L10n.isPL ? "Wiadomości z telefonu pojawią się tutaj."
                                                               : "Messages from your phone appear here."))
        }
    }

    /// The conversation appears only once its own messages are in: built
    /// then, with its content complete, the scroll view opens at the end.
    /// (Built earlier it showed the previous thread for a moment and was
    /// anchored against content that was about to change.)
    private func conversationView(_ convo: SmsConversationMeta) -> some View {
        let loaded = smsService.currentThreadId == convo.threadId && !smsService.currentMessages.isEmpty
        return Group {
            if loaded {
                messagesScroll(convo)
            } else if smsService.messagesLoadFailed {
                ContentUnavailableView {
                    Label(L10n.isPL ? "Nie udało się załadować wiadomości" : "Could Not Load Messages",
                          systemImage: "exclamationmark.triangle")
                } description: {
                    Text(L10n.isPL ? "Telefon nie odpowiedział. Spróbuj ponownie." : "The phone did not respond. Please try again.")
                } actions: {
                    Button(L10n.isPL ? "Spróbuj ponownie" : "Try Again") { smsService.loadMessages(threadId: convo.threadId) }
                }
            } else {
                // Plain background; the toolbar spinner says it is loading.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A Liquid Glass bar: the conversation scrolls under it and the
        // system's scroll edge effect keeps the field legible. It comes with
        // the messages, not before them.
        .safeAreaBar(edge: .bottom) {
            if loaded { replyBar(convo) }
        }
        // The conversation appears at once, at full size, without riding
        // the selection change's animation (bubbles grew in from nothing).
        .transaction { $0.animation = nil }
    }

    private func messagesScroll(_ convo: SmsConversationMeta) -> some View {
        // The phone sends newest first; the conversation reads oldest first.
        let messages = Array(smsService.currentMessages.reversed())
        return ScrollViewReader { proxy in ScrollView {
            // Not lazy: a page is 30 messages, laid out at once with their
            // real heights, so the conversation opens exactly at its end.
            VStack(spacing: 6) {
                // Older messages load as the conversation is scrolled to its top.
                if smsService.hasOlderMessages {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                    if index == 0 || msg.date - messages[index - 1].date > Self.burstGapMillis {
                        Text(Self.headerText(msg.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, index == 0 ? 8 : 16)
                            .padding(.bottom, 4)
                    }
                    MessageBubble(message: msg, query: searchQuery)
                        .id(msg.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.bottom)
        // A new message grows the content; the view stays at its end.
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        // Near the top, the next page back. Acts on the change into that
        // state, not on the first layout before the view settles at its end.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < Self.olderPageThreshold
                && geometry.contentSize.height > geometry.containerSize.height
        } action: { _, isNearTop in
            nearTop = isNearTop
            if isNearTop { loadOlderPage(above: messages.first?.id) }
        }
        // The top reached while a reopened thread was refreshing: that ask
        // was held, and goes out once the refresh is in. Only a held ask —
        // after every load it chained page after page while the view was
        // still at the top, before it returned to its anchor.
        .onChange(of: smsService.isLoadingMessages) { _, loading in
            guard !loading, olderPagePending else { return }
            olderPagePending = false
            if nearTop { loadOlderPage(above: messages.first?.id) }
        }
        // The older page lands above; the view returns to the message that
        // was on top, as Messages does. Left alone, it jumped to the very
        // top, the spinner stayed in sight and no further page was asked for.
        .onChange(of: smsService.currentMessages.count) {
            guard let anchor = olderPageAnchor else { return }
            olderPageAnchor = nil
            proxy.scrollTo(anchor, anchor: .top)
        }
        }
        // A fresh scroll view per conversation, so each opens at its end.
        .id(convo.id)
    }

    /// The next page back, the view to return to `anchor` once it is in.
    private func loadOlderPage(above anchor: SmsMessageMeta.ID?) {
        guard smsService.hasOlderMessages else { return }
        guard !smsService.isLoadingMessages else { olderPagePending = true; return }
        olderPageAnchor = anchor
        smsService.loadOlderMessages()
    }

    @ViewBuilder
    private func replyBar(_ convo: SmsConversationMeta) -> some View {
        if Self.isShortCode(convo.address) {
            Text(L10n.isPL ? "Nie można odpowiedzieć na tę wiadomość." : "You can't reply to this message.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(in: .capsule)
                .frame(maxWidth: .infinity)
                .padding(12)
        } else {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(L10n.isPL ? "Wiadomość SMS" : "Text Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: Self.barHeight)
                    .glassEffect(in: .rect(cornerRadius: Self.barHeight / 2, style: .continuous))
                    .onSubmit { send(to: convo) }
                // The same height as a one-line field, so the two line up.
                let canSend = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button { send(to: convo) } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canSend ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                        .frame(width: Self.barHeight, height: Self.barHeight)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(canSend ? .regular.tint(.accentColor).interactive() : .regular, in: .circle)
                .disabled(!canSend)
                .help(L10n.isPL ? "Wyślij" : "Send")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func send(to convo: SmsConversationMeta) {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        smsService.sendMessage(address: convo.address, body: text)
        messageText = ""
    }

    // MARK: - Formatting

    /// How close to the top of a conversation the next page back is asked for.
    private static let olderPageThreshold: CGFloat = 200

    /// Height of the one-line reply field and of the send button.
    private static let barHeight: CGFloat = 38

    /// Messages further apart than this get a time header between them.
    private static let burstGapMillis: Int64 = 60 * 60 * 1000

    /// A sender with letters in it ("InPost", "mBank") is a service that
    /// takes no replies.
    private static func isShortCode(_ address: String) -> Bool {
        address.contains { $0.isLetter }
    }

    /// "Dziś 14:32", "Wczoraj 09:10" or "3 paź 2026, 18:20".
    private static func headerText(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return (L10n.isPL ? "Dziś " : "Today ") + time }
        if calendar.isDateInYesterday(date) { return (L10n.isPL ? "Wczoraj " : "Yesterday ") + time }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A conversation in the list, as Messages draws one: the unread dot, the
/// contact symbol, the name with the date and two lines of the last message.
private struct ConversationRow: View {
    let conversation: SmsConversationMeta
    let isSelected: Bool
    let query: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                // White on the accent-coloured selection, where the tint would vanish.
                .fill(conversation.unreadCount > 0
                      ? (isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint)) : AnyShapeStyle(.clear))
                .frame(width: 8, height: 8)
                .padding(.top, 15)
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(SearchHighlight.text(conversation.displayName, query))
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.dateText(conversation.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(SearchHighlight.text(conversation.snippet, query))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    /// Time today, "Wczoraj", the weekday within a week, else the date.
    private static func dateText(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return L10n.isPL ? "Wczoraj" : "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

/// A message bubble: sent ones in the accent colour on the right, received
/// ones grey on the left, as Messages.
private struct MessageBubble: View {
    let message: SmsMessageMeta
    let query: String

    private var isSent: Bool { message.type == 2 }

    var body: some View {
        HStack {
            if isSent { Spacer(minLength: 0) }
            Text(SearchHighlight.text(message.body, query))
                .textSelection(.enabled)
                .foregroundStyle(isSent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSent ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary),
                            in: .rect(cornerRadius: 19, style: .continuous))
                // At most ~3/4 of the conversation's width, as Messages: a
                // long text wraps there, a short one keeps its own width.
                .containerRelativeFrame(.horizontal, alignment: isSent ? .trailing : .leading) { width, _ in
                    width * 0.72
                }
                .help(message.date == 0 ? "" : Date(timeIntervalSince1970: TimeInterval(message.date) / 1000)
                    .formatted(date: .abbreviated, time: .shortened))
            if !isSent { Spacer(minLength: 0) }
        }
    }
}

/// Search matches marked as the system marks found text (Safari, Messages):
/// the find-highlight colour behind them, dark text on it. Case and
/// diacritics are ignored, so "dzie" finds "Dzięki".
enum SearchHighlight {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func matches(_ text: String, _ query: String) -> Bool {
        query.isEmpty || text.range(of: query, options: options) != nil
    }

    static func text(_ text: String, _ query: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var searchStart = text.startIndex
        while let range = text.range(of: query, options: options, range: searchStart..<text.endIndex) {
            if let lower = AttributedString.Index(range.lowerBound, within: result),
               let upper = AttributedString.Index(range.upperBound, within: result) {
                result[lower..<upper].backgroundColor = Color(nsColor: .findHighlightColor)
                result[lower..<upper].foregroundColor = .black
            }
            searchStart = range.upperBound
        }
        return result
    }
}
