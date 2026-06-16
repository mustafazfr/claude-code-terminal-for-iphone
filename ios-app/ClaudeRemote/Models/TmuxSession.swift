import Foundation

/// Mac'teki bir tmux oturumu (`tmux list-sessions` çıktısından parse edilir).
struct TmuxSession: Identifiable, Hashable {
    let name: String
    let windows: Int
    let attached: Bool
    var id: String { name }
}
