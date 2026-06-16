import SwiftUI

/// Claude Code geçmiş sohbetleri — dokun, kaldığın yerden devam et (`claude --resume`).
struct ConversationsView: View {
    let host: Host
    let password: String

    @StateObject private var controller = ChatHistoryController()
    @State private var resume: ResumeTarget?

    var body: some View {
        List {
            switch controller.state {
            case .loading:
                HStack { ProgressView(); Text("Sohbetler yükleniyor…").foregroundStyle(.secondary) }

            case .failed(let message):
                Label("Yüklenemedi", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Tekrar dene") { Task { await controller.load(host: host, password: password) } }

            case .loaded(let chats):
                if chats.isEmpty {
                    ContentUnavailableView("Sohbet yok", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Bu Mac'te kayıtlı Claude Code sohbeti bulunamadı."))
                } else {
                    // Son sohbete göre düz liste (claude-sessions zaten tarihe göre sıralı).
                    Section {
                        ForEach(chats) { chat in
                            Button { resume = ResumeTarget(chat: chat) } label: {
                                ChatRow(chat: chat)
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("En son kullanılan üstte. Dokun → o sohbete kaldığın yerden devam et.")
                    }
                }
            }
        }
        .navigationTitle("Geçmiş Sohbetler")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await controller.load(host: host, password: password) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .navigationDestination(item: $resume) { target in
            // Doğru dizinde + tmux içinde resume; başlık projeyle anlamlı.
            TerminalScreen(
                host: host, password: password,
                title: target.chat.projectName,
                initialCommand: "claude-resume \(target.chat.sessionId) \(shellQuote(target.chat.cwd))"
            )
        }
        .task { await controller.load(host: host, password: password) }
        .refreshable { await controller.load(host: host, password: password) }
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct ResumeTarget: Identifiable, Hashable {
    let chat: ClaudeChat
    var id: String { chat.sessionId }
}

private struct ChatRow: View {
    let chat: ClaudeChat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chat.summary.isEmpty ? "(başlıksız)" : chat.summary)
                .font(.callout)
                .lineLimit(2)
            HStack(spacing: 6) {
                Label(chat.projectName, systemImage: "folder")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text("·").foregroundStyle(.secondary)
                Text(chat.date, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
