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
            // Ayraç '|'. 4. alan: o oturumun aktif pane'inde çalışan komut (boş kabuk ayıklama).
            let cmd = #"export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; "#
                + "tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}|#{pane_current_command}' 2>/dev/null; true"
            let output = try await conn.run(cmd)
            state = .loaded(Self.parse(output))
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// Mac'te kayıtlı Claude hesaplarını (claude-account list) döndürür.
    func accounts(host: Host, password: String) async -> [String] {
        let conn = ConnectionPool.connection(for: host, password: password)
        let cmd = #"export PATH="$HOME/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"; claude-account list 2>/dev/null; true"#
        guard let out = try? await conn.run(cmd) else { return [] }
        return out.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("(") }
    }

    /// Bir tmux oturumunu sonlandırır, sonra listeyi yeniler.
    func kill(session name: String, host: Host, password: String) async {
        let conn = ConnectionPool.connection(for: host, password: password)
        let cmd = #"export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"; "#
            + "tmux kill-session -t \(Shell.quote("=\(name)")) 2>/dev/null; true"
        _ = try? await conn.run(cmd)
        await load(host: host, password: password)
    }

    /// `#{session_name}|#{session_windows}|#{session_attached}|#{pane_current_command}` parse.
    static func parse(_ output: String) -> [TmuxSession] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            return TmuxSession(
                name: parts[0],
                windows: Int(parts[1]) ?? 1,
                attached: parts[2].trimmingCharacters(in: .whitespaces) == "1",
                command: parts.count >= 4 ? parts[3].trimmingCharacters(in: .whitespaces) : ""
            )
        }
    }
}
