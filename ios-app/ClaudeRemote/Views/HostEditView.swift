import SwiftUI

/// Mac ekleme/düzenleme formu. Anahtar (güvenli) veya parola seçilir.
struct HostEditView: View {
    @ObservedObject var store: HostStore
    let existing: Host?
    let onConnect: (Host, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hostname: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var savePassword: Bool
    @State private var auth: AuthMethod
    @State private var publicKey: String?
    @State private var keyError: String?
    @State private var showHelp = false

    init(store: HostStore, existing: Host?, onConnect: @escaping (Host, String) -> Void) {
        self.store = store
        self.existing = existing
        self.onConnect = onConnect
        _name = State(initialValue: existing?.name ?? "Evdeki Mac")
        _hostname = State(initialValue: existing?.hostname ?? "")
        _port = State(initialValue: String(existing?.port ?? 22))
        _username = State(initialValue: existing?.username ?? "mustafa")
        _password = State(initialValue: existing.flatMap { store.password(for: $0) } ?? "")
        _savePassword = State(initialValue: existing != nil)
        _auth = State(initialValue: existing?.auth ?? .key)
    }

    private var canConnect: Bool {
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac bilgileri") {
                    TextField("Görünen ad", text: $name)
                    TextField("Host — Mac'in IP'si (ör. 192.168.1.109)", text: $hostname)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Kullanıcı adı (Mac'te: whoami)", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", text: $port).keyboardType(.numberPad)
                }

                Section {
                    Picker("Giriş yöntemi", selection: $auth) {
                        Text("SSH Anahtarı (güvenli)").tag(AuthMethod.key)
                        Text("Parola").tag(AuthMethod.password)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(auth == .key
                         ? "Önerilen. İnternete açık ngrok için en güvenlisi: parola yok = kaba-kuvvet saldırısı yok. Anahtar Face ID ile korunur."
                         : "Parola yalnızca cihazının Keychain'inde saklanır. Güvenli ağlarda (ev Wi-Fi) pratiktir.")
                }

                if auth == .key {
                    keySection
                } else {
                    passwordSection
                }

                Section {
                    Button { showHelp = true } label: {
                        Label("Host adımı / kurulumu nasıl yaparım?", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle(existing == nil ? "Yeni Mac" : "Mac'i düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bağlan") { saveAndConnect() }.disabled(!canConnect).bold()
                }
            }
            .sheet(isPresented: $showHelp) { HelpView() }
            .onAppear(perform: ensureKey)
            .onChange(of: auth) { _, _ in ensureKey() }
        }
    }

    @ViewBuilder private var keySection: some View {
        Section {
            if let publicKey {
                Text(publicKey)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                Button {
                    UIPasteboard.general.string = publicKey
                } label: { Label("Genel anahtarı kopyala", systemImage: "doc.on.doc") }
                ShareLink(item: publicKey) {
                    Label("Paylaş (AirDrop ile Mac'e)", systemImage: "square.and.arrow.up")
                }
            } else if let keyError {
                Label(keyError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else {
                ProgressView()
            }
        } header: {
            Text("Bu anahtarı Mac'ine ekle (bir kez)")
        } footer: {
            Text("Mac'te Terminal'de şunu çalıştır:\nmkdir -p ~/.ssh && echo \"<yukarıdaki anahtar>\" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys")
                .font(.caption).textSelection(.enabled)
        }
    }

    @ViewBuilder private var passwordSection: some View {
        Section {
            SecureField("Parola", text: $password)
            Toggle("Parolayı kaydet (otomatik giriş)", isOn: $savePassword)
        }
    }

    private func ensureKey() {
        guard auth == .key, publicKey == nil else { return }
        do { publicKey = try SSHKeyStore.generateIfNeeded() }
        catch { keyError = error.localizedDescription }
    }

    private func saveAndConnect() {
        let host = Host(
            id: existing?.id ?? UUID(),
            name: name.isEmpty ? hostname : name,
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 22,
            username: username.trimmingCharacters(in: .whitespaces),
            auth: auth
        )
        // Parolayı yalnızca parola yönteminde sakla.
        store.add(host, password: auth == .password ? password : nil,
                  savePassword: auth == .password && savePassword)
        onConnect(host, auth == .password ? password : "")
    }
}
