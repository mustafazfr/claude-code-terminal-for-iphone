import Foundation
import SSHKit

/// Bir Mac'e TEK kalıcı SSH bağlantısı tutar ve kısa komutları (tmux list, kill, sohbet
/// geçmişi) onun üzerinden çalıştırır. Böylece her ekran için yeni bağlantı (yavaş relay'de
/// ~1sn) açılmaz — ilk bağlantıdan sonra komutlar anında döner.
///
/// Aynı Host.id için tek örnek paylaşılır (ConnectionPool). Terminal PTY'si ayrıdır
/// (uzun ömürlü kendi kanalını kullanır); bu yalnızca kısa "exec" komutları içindir.
actor SSHConnection {
    private let host: Host
    private let password: String
    private var client: SSHClient?

    init(host: Host, password: String) {
        self.host = host
        self.password = password
    }

    private func connectedClient() async throws -> SSHClient {
        if let c = client, c.isConnected { return c }
        let auth = try SSHAuth.method(for: host, password: password)
        let c = try await SSHClient.connect(
            host: host.hostname, port: host.port,
            authenticationMethod: auth,
            hostKeyValidator: HostKeyVerification.validator(for: host),
            reconnect: .never
        )
        client = c
        return c
    }

    /// Kısa bir komut çalıştırıp stdout'u string döndürür (kalıcı bağlantıyı tekrar kullanır).
    func run(_ command: String) async throws -> String {
        let c = try await connectedClient()
        let buffer = try await c.executeCommand(command, mergeStreams: false)
        return String(buffer: buffer)
    }

    /// Bir dosyayı SFTP ile uzak yola yükler (gerekirse klasörü oluşturur). Resim yükleme
    /// için: telefondan seçilen görseli Mac'e koyar, sonra yolu terminale yazılır.
    /// `remoteDir` ev dizinine göredir (SFTP varsayılanı). Tam yolu döndürür.
    func upload(data: Data, remoteDir: String, fileName: String) async throws -> String {
        let c = try await connectedClient()
        return try await c.withSFTP { sftp in
            // Klasör yoksa oluştur (varsa hatayı yut).
            try? await sftp.createDirectory(atPath: remoteDir)
            let path = "\(remoteDir)/\(fileName)"
            let file = try await sftp.openFile(filePath: path, flags: [.write, .create, .truncate])
            var buf = ByteBufferAllocator().buffer(capacity: data.count)
            buf.writeBytes(data)
            try await file.write(buf)
            try await file.close()
            return path
        }
    }

    func close() async {
        let c = client; client = nil
        try? await c?.close()
    }
}

/// Host.id başına tek SSHConnection paylaşır. MainActor'dan erişilir.
@MainActor
enum ConnectionPool {
    private static var pool: [UUID: SSHConnection] = [:]

    static func connection(for host: Host, password: String) -> SSHConnection {
        if let existing = pool[host.id] { return existing }
        let c = SSHConnection(host: host, password: password)
        pool[host.id] = c
        return c
    }

    static func drop(_ hostID: UUID) {
        if let c = pool.removeValue(forKey: hostID) {
            Task { await c.close() }
        }
    }
}
