import SwiftUI
import UIKit
import SSHKit   // SwiftTerm yeniden dışa verilmiş (TerminalView, TerminalViewDelegate)

/// SwiftTerm'in iOS `TerminalView`'ını SwiftUI'a saran yüzey.
/// - Terminal layout olup gerçek boyutu (cols/rows) belli olunca `onReady` ile bildirir;
///   bağlantı O BOYUTLA açılır (yazıların iç içe geçmesini önler).
/// - Host'tan gelen baytları terminale besler; kullanıcı girişini SSH'a yollar.
struct TerminalSurface: UIViewRepresentable {
    let session: SSHTerminalSession
    /// Terminal ilk kez gerçek boyutuna kavuşunca (cols, rows) ile çağrılır — bir kez.
    let onReady: (Int, Int) -> Void

    func makeUIView(context: Context) -> TerminalView {
        let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        terminal.terminalDelegate = context.coordinator
        terminal.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.backgroundColor = .black
        terminal.nativeForegroundColor = .white
        terminal.nativeBackgroundColor = .black
        context.coordinator.terminal = terminal

        // Host -> terminal (onData ana iş parçacığında çağrılır, feed güvenli).
        session.onData = { [weak terminal] bytes in
            terminal?.feed(byteArray: bytes[...])
        }
        return terminal
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(session: session, onReady: onReady) }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let session: SSHTerminalSession
        let onReady: (Int, Int) -> Void
        weak var terminal: TerminalView?
        private var didReady = false

        init(session: SSHTerminalSession, onReady: @escaping (Int, Int) -> Void) {
            self.session = session
            self.onReady = onReady
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            // İlk geçerli boyutta bağlantıyı tetikle; sonrakiler PTY'yi yeniden boyutlar.
            guard newCols > 0, newRows > 0 else { return }
            if !didReady {
                didReady = true
                onReady(newCols, newRows)
            } else {
                MainActor.assumeIsolated { session.resize(cols: newCols, rows: newRows) }
            }
        }

        // Kullanıcı girişi -> SSH (delegate ana iş parçacığında çağrılır).
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            MainActor.assumeIsolated { session.send(data) }
        }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        // Terminaldeki bir bağlantıya dokununca TELEFONUN tarayıcısında aç
        // (Claude Code login linki gibi). GÜVENLİK: yalnızca http/https — kötü niyetli
        // sunucunun garip şema (file:, javascript: vb.) URL'leri tetiklemesini engelle.
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
            else { return }
            MainActor.assumeIsolated { UIApplication.shared.open(url) }
        }
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
