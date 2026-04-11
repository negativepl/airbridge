import SwiftUI
import Protocol

struct MessagesView: View {
    let smsService: SmsService
    let connectionService: ConnectionService

    @State private var selectedConversation: SmsConversationMeta?
    @State private var messageText: String = ""
    @State private var displayedConversations: Int = 30
    private let conversationsPageSize: Int = 30

    var body: some View {
        HStack(spacing: 0) {
            conversationList
                .frame(width: 340)

            Divider()

            if let convo = selectedConversation {
                messageDetail(convo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !connectionService.isConnected {
                VStack(spacing: 12) {
                    Image(systemName: "message")
                        .font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text(L10n.isPL ? "Wiadomości" : "Messages")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(.secondary)
                    Text(L10n.isPL
                        ? "Połącz się z telefonem, aby przeglądać wiadomości."
                        : "Connect to your phone to browse messages.")
                        .font(.system(size: 14)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(L10n.isPL ? "Wybierz konwersację" : "Select a conversation")
                    .font(.system(size: 18))
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
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(smsService.conversations.prefix(displayedConversations)) { convo in
                            conversationRow(convo)
                        }

                        if displayedConversations < smsService.conversations.count {
                            ProgressView()
                                .controlSize(.regular)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .onAppear {
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 250_000_000)
                                        withAnimation(.airbridgeQuick) {
                                            displayedConversations = min(
                                                displayedConversations + conversationsPageSize,
                                                smsService.conversations.count
                                            )
                                        }
                                    }
                                }
                        }
                    }
                    .padding(10)
                }
                .onChange(of: smsService.conversations.count) { _, newCount in
                    if displayedConversations > newCount {
                        displayedConversations = min(conversationsPageSize, newCount)
                    }
                }
            }
        }
    }

    private func conversationRow(_ convo: SmsConversationMeta) -> some View {
        Button {
            selectedConversation = convo
            smsService.loadMessages(threadId: convo.threadId)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(convo.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(formatDate(convo.date))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(convo.snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassEffect(
            selectedConversation?.id == convo.id
                ? .regular.tint(.accentColor).interactive()
                : .regular.interactive(),
            in: .rect(cornerRadius: 12, style: .continuous)
        )
    }

    private func messageDetail(_ convo: SmsConversationMeta) -> some View {
        ScrollView {
            ScrollViewReader { proxy in
                LazyVStack(spacing: 14) {
                    if smsService.isLoadingMessages && smsService.currentMessages.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        ForEach(smsService.currentMessages.reversed()) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .onChange(of: smsService.currentMessages.count) { _, _ in
                    if let last = smsService.currentMessages.reversed().last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .contentMargins(.top, 72, for: .scrollContent)
        .contentMargins(.bottom, 80, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .overlay(alignment: .top) {
            messageDetailHeader(convo)
        }
        .overlay(alignment: .bottom) {
            messageDetailInput(convo)
        }
    }

    private func messageDetailHeader(_ convo: SmsConversationMeta) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(convo.displayName)
                    .font(.system(size: 16, weight: .semibold))
                Text(convo.address)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func messageDetailInput(_ convo: SmsConversationMeta) -> some View {
        if isShortCode(convo.address) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
                Text(L10n.isPL
                    ? "Nie możesz odpowiedzieć na ten krótki kod."
                    : "You can't reply to this short code.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        } else {
            HStack(spacing: 12) {
                TextField(L10n.isPL ? "Wiadomość..." : "Message...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
                    .onSubmit { sendMessage(to: convo) }

                Button {
                    sendMessage(to: convo)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
                .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    private func isShortCode(_ address: String) -> Bool {
        let cleaned = address.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "+", with: "")
        if cleaned.contains(where: { $0.isLetter }) { return true }
        return false
    }

    private func messageBubble(_ msg: SmsMessageMeta) -> some View {
        let isSent = msg.type == 2
        return HStack {
            if isSent { Spacer(minLength: 60) }

            VStack(alignment: isSent ? .trailing : .leading, spacing: 3) {
                Text(msg.body)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(
                        isSent ? .regular.tint(.accentColor) : .regular,
                        in: .rect(cornerRadius: 16, style: .continuous)
                    )

                Text(formatTime(msg.date))
                    .font(.system(size: 11))
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
