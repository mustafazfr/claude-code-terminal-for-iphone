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
        // Fare bildirimini kapat: SwiftTerm'in kendi pan'i Claude'a sürükle/tıkla göndermesin
        // (kaydırırken istemeden seçim/garip davranış olmasın). Bizim wheel'imiz zaten doğrudan
        // PTY'ye gider, bu bayraktan bağımsız — Claude kendi fare moduyla yorumlar.
        terminal.allowMouseReporting = false
        // SwiftTerm'in KENDİ klavye-üstü çubuğunu kapat: bizim InputAccessoryBar'ımızla
        // çakışıyor (çift/karışık çubuk = "klavye berbat"). Tek çubuk kalsın → bizimki.
        terminal.inputAccessoryView = nil
        context.coordinator.terminal = terminal

        // SwiftTerm'in mevcut pan recognizer'larını (seçim + UIScrollView) kapat ki TEK PARMAK
        // kaydırma onlarla çakışmasın (yoksa seçim/ok-tuşu tetikler). Dokunma, çift/uzun-basma
        // seçim ayrı gesture'lar — onlar kalır.
        terminal.isScrollEnabled = false
        for gr in terminal.gestureRecognizers ?? [] where gr is UIPanGestureRecognizer {
            gr.isEnabled = false
        }

        // TEK PARMAK kaydırma → fare-tekerleği olayı. Claude TUI alt-ekran kullandığı ve
        // tmux'ta geçmiş tutmadığı için kaydırma Claude'a tekerlek olarak gider, o da kendi
        // sohbet geçmişini kaydırır. (Sonradan eklenen mouse-pan bayrak false olduğu için
        // etkisiz; delegate ile eşzamanlı tanımaya da izin veriyoruz.)
        let scrollPan = UIPanGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleScrollPan(_:)))
        scrollPan.minimumNumberOfTouches = 1
        scrollPan.maximumNumberOfTouches = 1
        scrollPan.delegate = context.coordinator
        terminal.addGestureRecognizer(scrollPan)

        // Host -> terminal (onData ana iş parçacığında çağrılır, feed güvenli).
        session.onData = { [weak terminal] bytes in
            terminal?.feed(byteArray: bytes[...])
        }
        return terminal
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(session: session, onReady: onReady) }

    final class Coordinator: NSObject, TerminalViewDelegate, UIGestureRecognizerDelegate {
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

        // MARK: - İki parmak kaydırma → fare-tekerleği

        /// Her ~22pt dikey hareket için bir tekerlek olayı gönderir. Aşağı sürüklemek
        /// (parmak aşağı) geçmişe gitmek (tekerlek yukarı) demek — doğal kaydırma.
        private var scrollAccum: CGFloat = 0

        @objc func handleScrollPan(_ g: UIPanGestureRecognizer) {
            guard let terminal else { return }
            switch g.state {
            case .began:
                scrollAccum = 0
            case .changed:
                let dy = g.translation(in: terminal).y
                g.setTranslation(.zero, in: terminal)
                scrollAccum += dy
                let step: CGFloat = 22
                while scrollAccum >= step { scrollAccum -= step; session.sendWheel(up: true) }
                while scrollAccum <= -step { scrollAccum += step; session.sendWheel(up: false) }
            default:
                scrollAccum = 0
            }
        }

        // SwiftTerm'in kendi pan/scroll hareketleriyle aynı anda çalışabilsin.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
