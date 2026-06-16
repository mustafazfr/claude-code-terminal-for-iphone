import Foundation

/// Kabuk komutu kurarken argümanları güvenle tırnak içine alır (komut enjeksiyonu önleme).
/// Tek tırnak kullanır; içerideki tek tırnakları kaçırır. Her uzak komut argümanı bundan geçer.
enum Shell {
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
