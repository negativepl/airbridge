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
            // The one place that says the phone is sending something.
            if smsService.isLoadingConversations || smsService.isLoadingMessages {
                ToolbarItem(placement: .primaryAction) {
                    ProgressView().controlSize(.small)
                }
                .sharedBackgroundVisibility(.hidden)
            }
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

    private var filteredConversations: [SmsConversationMeta] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return smsService.conversations }
        return smsService.conversations.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.address.localizedCaseInsensitiveContains(query)
                || $0.snippet.localizedCaseInsensitiveContains(query)
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
                ConversationRow(conversation: convo)
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

    private func conversationView(_ convo: SmsConversationMeta) -> some View {
        // The phone sends newest first; the conversation reads oldest first.
        let messages = Array(smsService.currentMessages.reversed())
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        if index == 0 || msg.date - messages[index - 1].date > Self.burstGapMillis {
                            Text(Self.headerText(msg.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, index == 0 ? 8 : 16)
                                .padding(.bottom, 4)
                        }
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .overlay {
                if smsService.isLoadingMessages && smsService.currentMessages.isEmpty {
                    // Plain background; the toolbar spinner says it is loading.
                    Color(nsColor: .windowBackgroundColor)
                } else if smsService.messagesLoadFailed && smsService.currentMessages.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.isPL ? "Nie udało się załadować wiadomości" : "Could Not Load Messages",
                              systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(L10n.isPL ? "Telefon nie odpowiedział. Spróbuj ponownie." : "The phone did not respond. Please try again.")
                    } actions: {
                        Button(L10n.isPL ? "Spróbuj ponownie" : "Try Again") { smsService.loadMessages(threadId: convo.threadId) }
                    }
                }
            }
            .onChange(of: smsService.currentMessages.first?.id) { _, newest in
                if let newest { proxy.scrollTo(newest, anchor: .bottom) }
            }
            // A Liquid Glass bar: the conversation scrolls under it and the
            // system's scroll edge effect keeps the field legible.
            .safeAreaBar(edge: .bottom) {
                replyBar(convo)
            }
        }
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

/// A conversation in the list, as Messages draws one: the contact symbol, the
/// name with the date, two lines of the last message and an unread dot.
private struct ConversationRow: View {
    let conversation: SmsConversationMeta

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(conversation.unreadCount > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                .frame(width: 8, height: 8)
                .padding(.top, 15)
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.dateText(conversation.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(conversation.snippet)
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

    private var isSent: Bool { message.type == 2 }

    var body: some View {
        HStack {
            if isSent { Spacer(minLength: 0) }
            Text(message.body)
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
