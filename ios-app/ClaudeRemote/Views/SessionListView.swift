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
                    Button("Tekrar dene") { Task { await controller.load(host: host, password: password) } }
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
                        }
                    }
                } header: {
                    Text("Açık terminaller (tmux)")
                } footer: {
                    Text("Bir oturuma dokun → kaldığın yerden devam et. Oturumlar Mac'te yaşar; bağlantı kopsa bile kapanmaz.")
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
            TerminalScreen(host: host, password: password, title: target.name)
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
        .task { await controller.load(host: host, password: password) }
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
