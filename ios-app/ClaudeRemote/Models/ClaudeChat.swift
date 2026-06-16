import Foundation

/// Claude Code'un geçmiş bir sohbeti (`claude-sessions` çıktısından).
/// `cd <cwd> && claude --resume <id>` ile kaldığı yerden devam ettirilir.
struct ClaudeChat: Identifiable, Hashable {
    let sessionId: String
    let cwd: String
    let date: Date
    let summary: String
    var id: String { sessionId }

    /// Bulunduğu projenin kısa adı (cwd'nin son parçası).
    var projectName: String {
        (cwd as NSString).lastPathComponent
    }
}
