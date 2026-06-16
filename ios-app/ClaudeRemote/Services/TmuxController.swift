import Foundation
import SSHKit

/// Mac'teki tmux oturumlarını listeler. Paylaşılan kalıcı SSH bağlantısını (ConnectionPool)
/// kullanır → her yenilemede yeni bağlantı açmaz (yavaş relay'de büyük fark).
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
            let conn = ConnectionPool.connection(for: host, password: password)
            // Ayraç '|' (TAB raw-string'de bozuluyordu). PATH'e Homebrew'i ekle, hata yut.
            let cmd = #"export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; "#
                + "tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null; true"
            let output = try await conn.run(cmd)
            state = .loaded(Self.parse(output))
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// Bir tmux oturumunu sonlandırır, sonra listeyi yeniler.
    func kill(session name: String, host: Host, password: String) async {
        let conn = ConnectionPool.connection(for: host, password: password)
        let cmd = #"export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; "#
            + "tmux kill-session -t \(Shell.quote("=\(name)")) 2>/dev/null; true"
        _ = try? await conn.run(cmd)
        await load(host: host, password: password)
    }

    /// `#{session_name}|#{session_windows}|#{session_attached}` satırlarını parse eder.
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
