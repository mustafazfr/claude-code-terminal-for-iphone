import SwiftUI

/// Başlangıç ekranı: kayıtlı Mac listesi (dokun-bağlan, otomatik giriş) + yeni ekle + yardım.
struct ConnectView: View {
    @StateObject private var store = HostStore()
    @State private var opened: OpenedHost?
    @State private var editTarget: EditTarget?
    @State private var showHelp = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.hosts.isEmpty {
                        ContentUnavailableView {
                            Label("Kayıtlı Mac yok", systemImage: "desktopcomputer")
                        } description: {
                            Text("Bağlanmak için bir Mac ekle. Host adını bilmiyorsan sağ üstteki ? simgesine dokun.")
                        }
                    } else {
                        ForEach(store.hosts) { host in
                            Button { connect(host) } label: {
                                HostRowView(host: host, autoLogin: store.password(for: host) != nil)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            offsets.map { store.hosts[$0] }.forEach(store.delete)
                        }
                    }
                } header: {
                    Text("Kayıtlı Mac'ler")
                }

                Section {
                    Button {
                        editTarget = EditTarget(host: nil)
                    } label: {
                        Label("Yeni Mac ekle", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("ClaudeRemote")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .navigationDestination(item: $opened) { route in
                HostGateView(host: route.host, password: route.password)
            }
            .sheet(item: $editTarget) { target in
                HostEditView(store: store, existing: target.host) { host, password in
                    editTarget = nil
                    opened = OpenedHost(host: host, password: password)
                }
            }
            .sheet(isPresented: $showHelp) { HelpView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func connect(_ host: Host) {
        switch host.auth {
        case .key:
            opened = OpenedHost(host: host, password: "")   // anahtar; parola kullanılmaz
        case .password:
            if let password = store.password(for: host) {
                opened = OpenedHost(host: host, password: password)   // otomatik giriş
            } else {
                editTarget = EditTarget(host: host)   // parola yok → forma git
            }
        }
    }
}

/// Açılan Mac (oturum listesine geçiş için).
struct OpenedHost: Hashable, Identifiable {
    let host: Host
    let password: String
    var id: UUID { host.id }
}

/// Düzenleme sheet'i hedefi (host == nil → yeni).
struct EditTarget: Identifiable {
    let id = UUID()
    var host: Host?
}

private struct HostRowView: View {
    let host: Host
    let autoLogin: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                Text("\(host.username)@\(host.hostname):\(host.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if autoLogin {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
