import Foundation
import Security
import SSHKit   // NIOSSH (NIOSSHPublicKey, delegate), NIOCore (ByteBuffer), Crypto (SHA256)

/// Sunucu (Mac) host anahtarı parmak izlerini saklar — TOFU (ilk-kullanımda-güven) için.
/// Parmak izleri gizli değildir; ama bütünlük için Keychain'de tutulur (cihaz dışına çıkmaz,
/// Face ID gerektirmez — her bağlantıda sormaması için).
enum HostKeyStore {
    private static let service = "com.mustafa.clauderemote.hostkey"

    static func fingerprint(for hostID: UUID) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data, let s = String(data: d, encoding: .utf8) else { return nil }
        return s
    }

    static func store(_ fingerprint: String, for hostID: UUID) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID.uuidString,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(fingerprint.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Bu Mac için sabitlenmiş güveni sil (kullanıcı bilerek yeniden doğrulamak isterse).
    static func reset(for hostID: UUID) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID.uuidString,
        ] as CFDictionary)
    }

    static func hasPinned(_ hostID: UUID) -> Bool { fingerprint(for: hostID) != nil }
}

/// Host anahtarı uyuşmazlığı — olası ortadaki-adam (MITM) saldırısı.
struct HostKeyMismatch: Error, LocalizedError {
    let expected: String
    let got: String
    var errorDescription: String? {
        "GÜVENLİK UYARISI: Mac'in kimlik anahtarı DEĞİŞTİ. Bu, ortadaki-adam saldırısı olabilir. "
        + "Bağlantı reddedildi. Mac'i bilerek yeniden kurduysan, bu Mac için güveni sıfırla."
    }
}

/// TOFU host anahtarı doğrulayıcı: ilk bağlantıda parmak izini sabitler, sonra her seferinde
/// karşılaştırır; uyuşmazsa bağlantıyı REDDEDER. Kötü niyetli relay/ağ saldırganını engeller.
/// NIO event-loop thread'inde çağrılır; yalnızca thread-safe Keychain'e dokunur.
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let hostID: UUID
    init(hostID: UUID) { self.hostID = hostID }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        _ = hostKey.write(to: &buffer)
        let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) ?? []
        let digest = SHA256.hash(data: Data(bytes))
        let fp = digest.map { String(format: "%02x", $0) }.joined()

        if let pinned = HostKeyStore.fingerprint(for: hostID) {
            if pinned == fp {
                validationCompletePromise.succeed(())          // bilinen, güvenilen anahtar
            } else {
                validationCompletePromise.fail(HostKeyMismatch(expected: pinned, got: fp))  // DEĞİŞMİŞ → reddet
            }
        } else {
            HostKeyStore.store(fp, for: hostID)                 // ilk kez → sabitle (TOFU)
            validationCompletePromise.succeed(())
        }
    }
}

/// Bir host için host-key doğrulayıcıyı verir. Tüm bağlantı noktaları bunu kullanır
/// (artık .acceptAnything() YOK).
enum HostKeyVerification {
    static func validator(for host: Host) -> SSHHostKeyValidator {
        .custom(TOFUHostKeyValidator(hostID: host.id))
    }
}
