import SwiftUI

/// Yerel yazma kutusu: harfler telefonda anlık yazılır (ağ turu YOK → ping hissedilmez),
/// yalnızca Enter/Gönder'e basınca tüm satır + "\n" Mac'e gider. Uzak relay gecikmesi
/// (bore.pub ~140ms) sadece gönderimde bir kez yaşanır, her harfte değil.
///
/// Canlı/etkileşimli mod (tab-tamamlama, anlık TUI) için terminale dokunup ham klavye
/// hâlâ kullanılabilir; bu kutu "pingsiz" varsayılan yoldur. Özel tuşlar üstteki çubukta.
struct ComposerBar: View {
    let session: SSHTerminalSession
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Mesaj yaz — Enter ile gönder", text: $text)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 18))

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(text.isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(text.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private func send() {
        let line = text
        text = ""
        // Boş satırda bile Enter göndermek anlamlı (örn. onay istemi) → ham "\n".
        session.send(text: line + "\n")
        focused = true        // klavye açık kalsın, peş peşe yazılabilsin
    }
}
