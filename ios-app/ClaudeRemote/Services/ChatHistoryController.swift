import Foundation
import SSHKit

/// Mac'teki Claude Code sohbet geçmişini getirir (`claude-sessions` script'i).
@MainActor
final class ChatHistoryController: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([ClaudeChat])
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
            let cmd = #"export PATH="$HOME/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"; claude-sessions 60 2>/dev/null; true"#
            let buffer = try await client.executeCommand(cmd, mergeStreams: false)
            try? await client.close()
            state = .loaded(Self.parse(String(buffer: buffer)))
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// Satır biçimi: `<id>|<cwd>|<epoch>|<özet>`
    static func parse(_ output: String) -> [ClaudeChat] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            // En fazla 4 parçaya böl (özet '|' içerebilir diye limitli).
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 4, !parts[0].isEmpty else { return nil }
            let id = parts[0]
            let cwd = parts[1]
            let epoch = TimeInterval(parts[2]) ?? 0
            let summary = parts[3...].joined(separator: "|")
            return ClaudeChat(
                sessionId: id, cwd: cwd,
                date: Date(timeIntervalSince1970: epoch),
                summary: summary
            )
        }
    }
}
