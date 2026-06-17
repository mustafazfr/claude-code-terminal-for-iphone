import SwiftUI

/// Bağlanılan Mac'in terminal ekranı: SwiftTerm yüzeyi + mobil giriş çubuğu.
/// Açılışta `claude-tmux <session>` çalıştırır (oturum varsa bağlanır, yoksa
/// caffeinate'li yeni oturum açıp Claude Code'u başlatır).
struct TerminalScreen: View {
    let host: Host
    let password: String
    /// Başlıkta görünecek ad.
    var title: String = "main"
    /// Bağlanınca shell'e yazılacak komut. nil → varsayılan: `claude-tmux <title> [account]`.
    var initialCommand: String?
    /// Bu oturumda kullanılacak Claude hesabı (claude-account adı). Boş → varsayılan.
    var account: String = ""

    @StateObject private var ssh = SSHTerminalSession()

    private var startupCommand: String {
        if let initialCommand { return initialCommand }
        // session + hesap adı dışarıdan gelir; enjeksiyona karşı tırnakla.
        var cmd = "claude-tmux \(Shell.quote(title))"
        if !account.isEmpty { cmd += " \(Shell.quote(account))" }
        return cmd
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalSurface(session: ssh, onReady: { cols, rows in
                // Terminal gerçek boyutuna kavuşunca O BOYUTLA bağlan (render düzgün olsun).
                ssh.connect(
                    host: host, password: password,
                    cols: cols, rows: rows,
                    initialCommand: startupCommand
                )
            })
            InputAccessoryBar(session: ssh, host: host, password: password)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { statusBadge }
        }
        .overlay(alignment: .top) { failureBanner }
        .onDisappear { ssh.disconnect() }
    }

    @ViewBuilder private var statusBadge: some View {
        switch ssh.status {
        case .idle, .connecting:
            HStack(spacing: 4) { ProgressView().controlSize(.small); Text("bağlanıyor") .font(.caption) }
        case .connected:
            Image(systemName: "circle.fill").foregroundStyle(.green)
        case .closed:
            Image(systemName: "circle").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder private var failureBanner: some View {
        if case .failed(let message) = ssh.status {
            Text("Bağlantı hatası: \(message)")
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.9))
        }
    }
}
