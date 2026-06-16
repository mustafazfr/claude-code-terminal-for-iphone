import Foundation
import SSHKit

/// Mac'teki tmux oturumlarını listeler. Kısa ömürlü bir SSH bağlantısı açıp
/// `tmux list-sessions` çalıştırır, parse eder, kapatır (terminal PTY'sinden bağımsız).
@MainActor
final class TmuxController: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([TmuxSession])
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    func load(host: Host, password: String) async {
        state = .loading
        do {
            let auth = try SSHAuth.method(for: host, password: password)
            let client = try await SSHClient.connect(
                host: host.hostname, port: host.port,
                authenticationMethod: auth,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never
            )
            // tmux yoksa/oturum yoksa stderr'i yut → boş liste. PATH'e Homebrew'i ekle.
            // Ayraç olarak '|' kullanıyoruz (TAB raw-string'de düz metin '\t' olarak gidip bozuluyordu).
            let cmd = #"export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; "#
                + "tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null; true"
            let buffer = try await client.executeCommand(cmd, mergeStreams: false)
            try? await client.close()

            let output = String(buffer: buffer)
            state = .loaded(Self.parse(output))
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// `tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}'`
    /// çıktısını parse eder. Her satır: ad | pencere_sayısı | (1=bağlı / 0=ayrık)
    /// AYRAÇ komuttaki (satır ~29) ile AYNI olmalı: '|'.
    static func parse(_ output: String) -> [TmuxSession] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            return TmuxSession(
                name: parts[0],
                windows: Int(parts[1]) ?? 1,
                attached: parts[2].trimmingCharacters(in: .whitespaces) == "1"
            )
        }
    }
}
