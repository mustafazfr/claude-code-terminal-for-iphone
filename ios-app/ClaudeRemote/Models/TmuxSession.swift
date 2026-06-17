import Foundation

/// Mac'teki bir tmux oturumu (`tmux list-sessions` çıktısından parse edilir).
struct TmuxSession: Identifiable, Hashable {
    let name: String
    let windows: Int
    let attached: Bool
    /// O an pane'de çalışan komut (claude, zsh, vim...). Boş kabuk ayıklamada kullanılır.
    let command: String

    var id: String { name }

    /// İçinde gerçek bir program çalışıyor mu (boş login kabuğu değil)?
    var isActive: Bool {
        let shells: Set<String> = ["zsh", "bash", "sh", "-zsh", "-bash", "login", "fish"]
        return !shells.contains(command.lowercased())
    }

    /// Listede gösterilecek okunaklı etiket.
    var activityLabel: String {
        if command == "claude" || command == "claude.exe" { return "Claude çalışıyor" }
        if isActive { return command }
        return "boş kabuk"
    }
}
