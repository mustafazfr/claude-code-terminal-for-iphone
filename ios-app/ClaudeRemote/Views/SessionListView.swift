import SwiftUI

/// Mac'teki açık tmux oturumlarını ("açık terminaller") listeler; dokun → bağlan,
/// "+ Yeni" → yeni oturum aç. Kullanıcının "açık terminalleri gör / yeni aç" isteği.
struct SessionListView: View {
    let host: Host
    let password: String

    @StateObject private var controller = TmuxController()
    @State private var terminal: TerminalTarget?
    @State private var showNewSheet = false
    @State private var newName = ""
    @State private var accounts: [String] = []
    @State private var selectedAccount: String = ""

    var body: some View {
        List {
            switch controller.state {
            case .loading:
                HStack { ProgressView(); Text("Oturumlar yükleniyor…").foregroundStyle(.secondary) }

            case .failed(let message):
                Section {
                    Label("Bağlanılamadı", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    if message.contains("HostKeyMismatch") || message.lowercased().contains("değişti") {
                        Text("Mac'in kimlik anahtarı kayıtlıdan farklı. Mac'i yeniden kurduysan güveni sıfırla; sen yapmadıysan bağlanma.")
                            .font(.caption).foregroundStyle(.red)
                        Button(role: .destructive) {
                            HostKeyStore.reset(for: host.id)
                            ConnectionPool.drop(host.id)
                            Task { await controller.load(host: host, password: password) }
                        } label: { Label("Güveni sıfırla ve yeniden dene", systemImage: "arrow.triangle.2.circlepath") }
                    } else {
                        Button("Tekrar dene") {
                            ConnectionPool.drop(host.id)
                            Task { await controller.load(host: host, password: password) }
                        }
                    }
                }

            case .loaded(let sessions):
                Section {
                    if sessions.isEmpty {
                        Text("Açık oturum yok. Aşağıdan yeni bir tane başlat.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions) { s in
                            Button { terminal = TerminalTarget(name: s.name) } label: {
                                SessionRow(session: s)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await controller.kill(session: s.name, host: host, password: password) }
                                } label: { Label("Kapat", systemImage: "trash") }
                            }
                        }
                    }
                } header: {
                    Text("Açık terminaller (tmux)")
                } footer: {
                    Text("Bir oturuma dokun → kaldığın yerden devam et. Oturumlar Mac'te yaşar; bağlantı kopsa bile kapanmaz. Sola kaydır → kapat.")
                }
            }

            if accounts.count > 1 {
                Section {
                    Picker("Claude hesabı", selection: $selectedAccount) {
                        ForEach(accounts, id: \.self) { Text($0).tag($0) }
                    }
                } header: {
                    Text("Hesap")
                } footer: {
                    Text("Yeni açılan terminaller bu Claude hesabıyla çalışır.")
                }
            }

            Section {
                Button { newName = ""; showNewSheet = true } label: {
                    Label("Yeni terminal aç", systemImage: "plus.circle.fill")
                }
                Button { terminal = TerminalTarget(name: "main") } label: {
                    Label("Hızlı başlat (main)", systemImage: "bolt.fill")
                }
                NavigationLink {
                    ConversationsView(host: host, password: password)
                } label: {
                    Label("Geçmiş sohbetler (devam et)", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await controller.load(host: host, password: password) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .navigationDestination(item: $terminal) { target in
            TerminalScreen(host: host, password: password, title: target.name, account: selectedAccount)
        }
        .alert("Yeni terminal", isPresented: $showNewSheet) {
            TextField("Oturum adı (örn. proje1)", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Aç") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                terminal = TerminalTarget(name: name.isEmpty ? "main" : sanitized(name))
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu adla bir oturum varsa ona bağlanır, yoksa yeni açar.")
        }
        .task {
            await controller.load(host: host, password: password)
            accounts = await controller.accounts(host: host, password: password)
            // Varsayılan hesabı seç (host'taki ya da ilk hesap).
            if selectedAccount.isEmpty {
                selectedAccount = accounts.contains(host.account) ? host.account : (accounts.first ?? "")
            }
        }
        .refreshable { await controller.load(host: host, password: password) }
    }

    /// tmux oturum adında sorun çıkaran karakterleri temizle.
    private func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(name.unicodeScalars.filter { allowed.contains($0) })
    }
}

/// Terminale yönlendirme hedefi (tmux oturum adı).
struct TerminalTarget: Identifiable, Hashable {
    let name: String
    var id: String { name }
}

private struct SessionRow: View {
    let session: TmuxSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).font(.body)
                Text("\(session.windows) pencere\(session.attached ? " · bağlı" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
