import Foundation

/// Kayıtlı Mac'leri kalıcı tutar (UserDefaults'ta JSON). Parolalar ayrıca Keychain'de.
@MainActor
final class HostStore: ObservableObject {
    @Published private(set) var hosts: [Host] = []
    private let key = "saved_hosts_v1"

    init() { load() }

    /// Host'u ekler/günceller. İstenirse parolayı Keychain'e yazar (otomatik giriş).
    func add(_ host: Host, password: String?, savePassword: Bool) {
        hosts.removeAll { $0.id == host.id }
        hosts.append(host)
        persist()
        if savePassword, let password, !password.isEmpty {
            KeychainStore.savePassword(password, for: host.id)
        } else {
            KeychainStore.deletePassword(for: host.id)
        }
    }

    func delete(_ host: Host) {
        hosts.removeAll { $0.id == host.id }
        persist()
        KeychainStore.deletePassword(for: host.id)
    }

    func password(for host: Host) -> String? {
        KeychainStore.password(for: host.id)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Host].self, from: data) else { return }
        hosts = decoded
    }
}
