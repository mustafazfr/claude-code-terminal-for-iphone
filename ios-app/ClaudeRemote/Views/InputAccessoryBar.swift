import SwiftUI
import PhotosUI

/// Mobil klavyede olmayan tuşlar + kaydırma + resim yükleme için yatay çubuk.
/// Baytları doğrudan SSH'a yollar (uzak uç yankılar).
struct InputAccessoryBar: View {
    let session: SSHTerminalSession
    /// SFTP ile resim yüklemek için (terminal PTY'si dosya aktaramaz; ayrı kanal gerekir).
    let host: Host
    let password: String

    @State private var photo: PhotosPickerItem?
    @State private var uploadState: UploadState = .idle

    enum UploadState: Equatable {
        case idle, uploading, done(String), failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            if uploadState != .idle { uploadBanner }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Resim yükle: telefondan seç → Mac'e SFTP ile koy → yolu prompt'a yaz.
                    PhotosPicker(selection: $photo, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .frame(minWidth: 34).padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.accentColor.opacity(0.22))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    // Kaydırma: Claude'a fare-tekerleği gönder (alt-ekran TUI kendi geçmişini
                    // kaydırır). Asıl yöntem iki parmakla kaydırma; bunlar yedek/ince ayar.
                    key("⤒") { for _ in 0..<3 { session.sendWheel(up: true) } }
                    key("⤓") { for _ in 0..<3 { session.sendWheel(up: false) } }

                    divider
                    key("esc")  { session.send(ArraySlice([0x1b])) }
                    key("tab")  { session.send(ArraySlice([0x09])) }
                    key("^C")   { session.send(ArraySlice([0x03])) }
                    key("^D")   { session.send(ArraySlice([0x04])) }
                    key("^L")   { session.send(ArraySlice([0x0c])) }
                    key("^R")   { session.send(ArraySlice([0x12])) }
                    divider
                    key("↑")    { session.send(ArraySlice([0x1b, 0x5b, 0x41])) }
                    key("↓")    { session.send(ArraySlice([0x1b, 0x5b, 0x42])) }
                    key("←")    { session.send(ArraySlice([0x1b, 0x5b, 0x44])) }
                    key("→")    { session.send(ArraySlice([0x1b, 0x5b, 0x43])) }
                    divider
                    key("|")    { session.send(text: "|") }
                    key("~")    { session.send(text: "~") }
                    key("/")    { session.send(text: "/") }
                    key("-")    { session.send(text: "-") }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .background(.ultraThinMaterial)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    @ViewBuilder private var uploadBanner: some View {
        Group {
            switch uploadState {
            case .uploading:
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Resim yükleniyor…") }
            case .done(let path):
                Label("Yüklendi: \(path)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            case .idle:
                EmptyView()
            }
        }
        .font(.caption2).lineLimit(1).truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 4)
    }

    /// Seçilen görseli SFTP ile Mac'e yükler, sonra yolunu prompt'a yazar (Claude okuyabilir).
    private func upload(_ item: PhotosPickerItem) async {
        uploadState = .uploading
        photo = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                uploadState = .failed("Görsel okunamadı"); return
            }
            let ext = data.isPNG ? "png" : "jpg"
            let name = "img-\(UUID().uuidString.prefix(8)).\(ext)"
            let conn = ConnectionPool.connection(for: host, password: password)
            // Ev dizinine göre 'claude-uploads/'; Claude'un okuması için mutlak yol oluştur.
            _ = try await conn.upload(data: data, remoteDir: "claude-uploads", fileName: name)
            let absolute = "/Users/\(host.username)/claude-uploads/\(name)"
            session.send(text: absolute + " ")
            uploadState = .done(name)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if case .done = uploadState { uploadState = .idle }
        } catch {
            uploadState = .failed("Yükleme başarısız: \(error.localizedDescription)")
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1, height: 22)
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.callout, design: .monospaced))
                .frame(minWidth: 34)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private extension Data {
    /// PNG imzası (‰PNG) ile basit tür tespiti; değilse jpg varsay.
    var isPNG: Bool { count >= 8 && self[0] == 0x89 && self[1] == 0x50 && self[2] == 0x4E && self[3] == 0x47 }
}
