import Foundation
import SSHKit

/// İlk bağlantı doğrulaması: Mac'in host anahtarı parmak izini bir kez "yoklayıp" (probe)
/// kullanıcıya gösterir. Kullanıcı Mac'le (claude-doctor) karşılaştırıp onaylarsa sabitler.
/// Bu, TOFU'nun tek açığını (ilk bağlantıda MITM) kapatır.
@MainActor
final class HostVerifier: ObservableObject {
    enum State: Equatable {
        case idle
        case probing
        case needsApproval(fingerprint: String)   // ilk kez: onayla ve sabitle
        case mismatch(pinned: String, got: String) // pinli ≠ gelen: MITM ya da Mac yeniden kuruldu
        case verified          // sabitli ve eşleşiyor / onaylandı
        case failed(String)
    }
    @Published private(set) var state: State = .idle

    /// Her zaman canlı anahtarı yoklar; pinliyse karşılaştırır (yanlış pin'i de yakalar).
    func start(host: Host, password: String) async {
        state = .probing
        do {
            let fp = try await probeFingerprint(host: host, password: password)
            if let pinned = HostKeyStore.fingerprint(for: host.id) {
                state = (pinned == fp) ? .verified : .mismatch(pinned: pinned, got: fp)
            } else {
                state = .needsApproval(fingerprint: fp)
            }
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// Kullanıcı "eşleşiyor" dedi → sabitle.
    func approve(host: Host) {
        if case .needsApproval(let fp) = state {
            HostKeyStore.store(fp, for: host.id)
            state = .verified
        }
    }

    /// Mac'i bilerek yeniden kurmuş; eski pin'i at, yeni anahtarı sabitle.
    func resetAndTrust(host: Host) {
        if case .mismatch(_, let got) = state {
            HostKeyStore.store(got, for: host.id)
            state = .verified
        }
    }

    /// Host anahtarını kaydeden ama bağlantıyı tamamlamaya çalışan probe. Anahtar,
    /// kullanıcı kimlik doğrulamasından ÖNCE (transport el sıkışmasında) görülür; bu yüzden
    /// auth başarısız olsa bile parmak izini elde ederiz.
    private func probeFingerprint(host: Host, password: String) async throws -> String {
        let recorder = RecordingValidator()
        let auth = try SSHAuth.method(for: host, password: password)
        do {
            let client = try await SSHClient.connect(
                host: host.hostname, port: host.port,
                authenticationMethod: auth,
                hostKeyValidator: .custom(recorder),
                reconnect: .never
            )
            try? await client.close()
        } catch {
            // auth/başka sebeple kapanmış olabilir; yine de parmak izini almış olabiliriz.
        }
        guard let fp = recorder.fingerprint else {
            throw ProbeFailed()
        }
        return fp
    }

    struct ProbeFailed: Error, LocalizedError {
        var errorDescription: String? { "Mac'e ulaşılamadı; host/port'u ve bağlantını kontrol et." }
    }
}

/// Sunucu anahtarını kaydeden, bağlantıya izin veren doğrulayıcı (yalnızca probe için).
/// validateHostKey NIO event-loop thread'inde çağrılır; kilitle koru.
private final class RecordingValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _fp: String?
    var fingerprint: String? { lock.lock(); defer { lock.unlock() }; return _fp }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fp = HostKeyFingerprint.make(hostKey)
        lock.lock(); _fp = fp; lock.unlock()
        validationCompletePromise.succeed(())
    }
}
