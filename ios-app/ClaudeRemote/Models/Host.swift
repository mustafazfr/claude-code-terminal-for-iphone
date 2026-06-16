import Foundation

/// SSH kimlik doğrulama yöntemi.
enum AuthMethod: String, Codable, CaseIterable {
    case key       // SSH anahtarı (ngrok/internet için önerilen — parola yok = brute-force yok)
    case password  // parola (ev Wi-Fi / Tailscale gibi güvenli ağlarda pratik)
}

/// Kayıtlı bir Mac bağlantısı.
/// ngrok ile: hostname = ngrok TCP adresi (örn. 0.tcp.eu.ngrok.io), port = ngrok portu.
struct Host: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var hostname: String
    var port: Int = 22
    var username: String
    var auth: AuthMethod = .key

    // Eski kayıtlarda `auth` olmayabilir → key varsay.
    enum CodingKeys: String, CodingKey { case id, name, hostname, port, username, auth }
    init(id: UUID = UUID(), name: String, hostname: String, port: Int = 22, username: String, auth: AuthMethod = .key) {
        self.id = id; self.name = name; self.hostname = hostname
        self.port = port; self.username = username; self.auth = auth
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        hostname = try c.decode(String.self, forKey: .hostname)
        port = try c.decode(Int.self, forKey: .port)
        username = try c.decode(String.self, forKey: .username)
        auth = try c.decodeIfPresent(AuthMethod.self, forKey: .auth) ?? .key
    }
}
