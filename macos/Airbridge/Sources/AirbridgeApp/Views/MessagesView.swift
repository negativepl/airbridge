import SwiftUI
import Protocol

struct MessagesView: View {
    let smsService: SmsService
    let connectionService: ConnectionService

    @State private var selectedConversation: SmsConversationMeta?
    @State private var messageText: String = ""

    var body: some View {
        HSplitView {
            conversationList
                .frame(minWidth: 250, maxWidth: 300)

            if let convo = selectedConversation {
                messageDetail(convo)
            } else if !connectionService.isConnected {
                VStack(spacing: 12) {
                    Image(systemName: "message")
                        .font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text(L10n.isPL ? "Wiadomości" : "Messages")
                        .font(.title3).fontWeight(.semibold).foregroundStyle(.secondary)
                    Text(L10n.isPL
                        ? "Połącz się z telefonem, aby przeglądać wiadomości."
                        : "Connect to your phone to browse messages.")
                        .font(.subheadline).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(L10n.isPL ? "Wybierz konwersację" : "Select a conversation")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if connectionService.isConnected && smsService.conversations.isEmpty {
                smsService.loadConversations()
            }
        }
        .onChange(of: connectionService.isConnected) { _, connected in
            if connected && smsService.conversations.isEmpty {
                smsService.loadConversations()
            }
        }
    }

    private var conversationList: some View {
        VStack(spacing: 0) {
            if smsService.isLoadingConversations && smsService.conversations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                conversationListContent
            }
        }
    }

    private var conversationListContent: some View {
        List(smsService.conversations, selection: $selectedConversation) { convo in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(convo.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(formatDate(convo.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(convo.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 4)
            .tag(convo)
        }
        .onChange(of: selectedConversation) { _, newConvo in
            if let convo = newConvo {
                smsService.loadMessages(threadId: convo.threadId)
            }
        }
    }

    private func messageDetail(_ convo: SmsConversationMeta) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(convo.displayName).font(.headline)
                    Text(convo.address).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.bar)

            Divider()

            // Messages
            if smsService.isLoadingMessages && smsService.currentMessages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(spacing: 8) {
                            ForEach(smsService.currentMessages.reversed()) { msg in
                                messageBubble(msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(12)
                        .onChange(of: smsService.currentMessages.count) { _, _ in
                            if let last = smsService.currentMessages.reversed().last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Input or short code warning
            if isShortCode(convo.address) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(L10n.isPL
                        ? "Nie możesz odpowiedzieć na ten krótki kod. Krótkie kody to numery używane do wysyłania automatycznych wiadomości — odpowiadanie na nie nie jest możliwe."
                        : "You can't reply to this short code. Short codes are numbers used to send automated messages — replying is not supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            } else {
                HStack(spacing: 8) {
                    TextField(L10n.isPL ? "Wiadomość..." : "Message...", text: $messageText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { sendMessage(to: convo) }

                    Button {
                        sendMessage(to: convo)
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
            }
        }
    }

    /// Short codes contain letters (like "msg007") or are very short non-numeric numbers.
    /// Pure digit numbers (even short ones like "5555") are allowed.
    private func isShortCode(_ address: String) -> Bool {
        let cleaned = address.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "+", with: "")
        // Contains letters → definitely a short code
        if cleaned.contains(where: { $0.isLetter }) { return true }
        return false
    }

    private func messageBubble(_ msg: SmsMessageMeta) -> some View {
        let isSent = msg.type == 2
        return HStack {
            if isSent { Spacer(minLength: 60) }

            VStack(alignment: isSent ? .trailing : .leading, spacing: 2) {
                Text(msg.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSent ? Color.accentColor : Color.gray.opacity(0.2))
                    .foregroundStyle(isSent ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(formatTime(msg.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isSent { Spacer(minLength: 60) }
        }
    }

    private func sendMessage(to convo: SmsConversationMeta) {
        let text = messageText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        smsService.sendMessage(address: convo.address, body: text)
        messageText = ""
    }

    private func formatDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let f = DateFormatter()
            f.timeStyle = .short
            return f.string(from: date)
        } else {
            let f = DateFormatter()
            f.dateStyle = .short
            return f.string(from: date)
        }
    }

    private func formatTime(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
