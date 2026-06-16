import Foundation
import Security
import SSHKit   // NIOSSH (NIOSSHPublicKey, delegate), NIOCore (ByteBuffer), Crypto (SHA256)

/// Sunucu (Mac) host anahtarı parmak izlerini saklar — TOFU (ilk-kullanımda-güven) için.
/// Parmak izleri gizli değildir; bütünlük için Keychain'de tutulur (cihaz dışına çıkmaz).
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

    static func reset(for hostID: UUID) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID.uuidString,
        ] as CFDictionary)
    }

    static func hasPinned(_ hostID: UUID) -> Bool { fingerprint(for: hostID) != nil }
}

/// Host anahtarının OpenSSH biçimli parmak izini üretir: `SHA256:<base64(sha256(keyblob))>`.
/// `ssh-keygen -lf` ile BİREBİR aynı çıktıyı verir → kullanıcı Mac'le gözle karşılaştırabilir.
enum HostKeyFingerprint {
    static func make(_ hostKey: NIOSSHPublicKey) -> String {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        _ = hostKey.write(to: &buffer)   // SSH telgraf (wire) biçimi = OpenSSH'in hash'lediği blob
        let blob = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) ?? []
        let digest = Data(SHA256.hash(data: Data(blob)))
        // OpenSSH: base64, sondaki '=' dolgusu atılır.
        let b64 = digest.base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(b64)"
    }
}

/// Host anahtarı uyuşmazlığı — olası ortadaki-adam (MITM) saldırısı.
struct HostKeyMismatch: Error, LocalizedError {
    var errorDescription: String? {
        "GÜVENLİK UYARISI: Mac'in kimlik anahtarı DEĞİŞTİ. Ortadaki-adam saldırısı olabilir; bağlantı reddedildi. "
        + "Mac'i bilerek yeniden kurduysan, Mac ayarlarından 'güveni sıfırla'."
    }
}

/// İlk bağlantı: kullanıcı bu parmak izini Mac'le karşılaştırıp onaylamalı.
struct HostKeyUnverified: Error {
    let fingerprint: String
}

/// Host anahtarı doğrulayıcı:
/// - Sabitli ve eşleşiyor → kabul.
/// - Sabitli ama farklı → REDDET (MITM).
/// - Hiç sabitli değil → `pendingFingerprint`'e yaz ve REDDET (kullanıcı onayı beklenir).
///   Kullanıcı onaylayınca `HostKeyStore.store` ile sabitlenir ve tekrar bağlanılır.
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let hostID: UUID
    init(hostID: UUID) { self.hostID = hostID }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fp = HostKeyFingerprint.make(hostKey)
        if let pinned = HostKeyStore.fingerprint(for: hostID) {
            if pinned == fp {
                validationCompletePromise.succeed(())          // bilinen, güvenilen anahtar
            } else {
                validationCompletePromise.fail(HostKeyMismatch())  // DEĞİŞMİŞ → reddet (MITM)
            }
        } else {
            // Sabitli değil. HostGateView, bağlanmadan önce kullanıcıya doğrulatıp sabitler;
            // buraya düşmek demek henüz onaylanmamış demektir → reddet.
            validationCompletePromise.fail(HostKeyUnverified(fingerprint: fp))
        }
    }
}

enum HostKeyVerification {
    static func validator(for host: Host) -> SSHHostKeyValidator {
        .custom(TOFUHostKeyValidator(hostID: host.id))
    }
}
