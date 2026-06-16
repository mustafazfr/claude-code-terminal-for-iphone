import Foundation
import Security
import SSHKit   // Crypto (Curve25519) yeniden dışa verilmiş

/// Uygulamanın SSH kimliği: tek bir Ed25519 anahtar çifti.
/// - Özel anahtar: Keychain'de **Face ID/parola** (userPresence) arkasında — cihazdan asla çıkmaz.
/// - Genel anahtar: OpenSSH formatında (Mac'in authorized_keys'ine eklenecek), gizli değil.
///
/// Bu, "internetten yetkisiz erişim" savunmasının temelidir: özel anahtar olmadan
/// SSH'a girilemez; Face ID katmanı da telefon çalınırsa anahtarı korur.
enum SSHKeyStore {
    private static let service = "com.mustafa.clauderemote.sshkey"
    private static let account = "default-ed25519"
    private static let pubDefaultsKey = "ssh_public_key_openssh_v1"

    enum KeyError: LocalizedError {
        case keychain(OSStatus)
        case accessControl
        var errorDescription: String? {
            switch self {
            case .keychain(let s): return "Keychain hatası (\(s))"
            case .accessControl:   return "Güvenli saklama (Face ID) ayarlanamadı"
            }
        }
    }

    /// Daha önce üretilmiş genel anahtar (varsa). Face ID GEREKTİRMEZ.
    static var publicKeyOpenSSH: String? {
        UserDefaults.standard.string(forKey: pubDefaultsKey)
    }

    static var hasKey: Bool { publicKeyOpenSSH != nil }

    /// Anahtar yoksa üretir; her durumda genel anahtarı (OpenSSH) döndürür.
    @discardableResult
    static func generateIfNeeded() throws -> String {
        if let existing = publicKeyOpenSSH { return existing }
        let priv = Curve25519.Signing.PrivateKey()
        try savePrivateKey(priv.rawRepresentation)
        let pub = openSSHString(priv.publicKey, comment: "clauderemote@iphone")
        UserDefaults.standard.set(pub, forKey: pubDefaultsKey)
        return pub
    }

    /// Uygulama açık olduğu sürece anahtarı bellekte tutar → her bağlantıda Face ID
    /// sormaz (oturum listesi, terminal, yenileme... hepsi tek doğrulamayı paylaşır).
    /// Anahtar Keychain'de yine Face ID arkasında durur; bu yalnızca süreç-içi önbellek.
    private static var cachedKey: Curve25519.Signing.PrivateKey?

    /// Bellekteki önbelleği temizler (örn. "kilitle" için ileride kullanılabilir).
    static func lock() { cachedKey = nil }

    /// Bağlanırken çağrılır. İlk seferde Face ID sorar; sonra bellekten verir.
    static func loadPrivateKey(prompt: String) throws -> Curve25519.Signing.PrivateKey {
        if let cachedKey { return cachedKey }
        let key = try loadFromKeychain(prompt: prompt)
        cachedKey = key
        return key
    }

    private static func loadFromKeychain(prompt: String) throws -> Curve25519.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseOperationPrompt as String: prompt,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeyError.keychain(status)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    static func deleteKey() {
        cachedKey = nil
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        UserDefaults.standard.removeObject(forKey: pubDefaultsKey)
    }

    // MARK: - Özel

    private static func savePrivateKey(_ data: Data) throws {
        var cfError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,           // Face ID / Touch ID, yoksa cihaz parolası
            &cfError
        ) else { throw KeyError.accessControl }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyError.keychain(status) }
    }

    /// Curve25519 genel anahtarını OpenSSH `authorized_keys` satırına çevirir:
    /// `ssh-ed25519 <base64( str("ssh-ed25519") + str(32-byte-key) )> comment`
    private static func openSSHString(_ pub: Curve25519.Signing.PublicKey, comment: String) -> String {
        func lengthPrefixed(_ d: Data) -> Data {
            var be = UInt32(d.count).bigEndian
            var out = Data(bytes: &be, count: 4)
            out.append(d)
            return out
        }
        var blob = Data()
        blob.append(lengthPrefixed(Data("ssh-ed25519".utf8)))
        blob.append(lengthPrefixed(pub.rawRepresentation))
        return "ssh-ed25519 \(blob.base64EncodedString()) \(comment)"
    }
}
