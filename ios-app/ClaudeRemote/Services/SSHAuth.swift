import Foundation
import SSHKit

/// Host'un seçili yöntemine göre SSH kimlik doğrulaması üretir.
/// - .key  → Keychain'den özel anahtarı çözer (Face ID sorar) → Ed25519.
/// - .password → parola.
enum SSHAuth {
    static func method(for host: Host, password: String) throws -> SSHAuthenticationMethod {
        switch host.auth {
        case .password:
            return .passwordBased(username: host.username, password: password)
        case .key:
            let key = try SSHKeyStore.loadPrivateKey(prompt: "\(host.name) için kimliğini doğrula")
            return .ed25519(username: host.username, privateKey: key)
        }
    }
}
