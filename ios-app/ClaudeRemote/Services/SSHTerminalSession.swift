import Foundation
import SSHKit   // Citadel + NIOCore + NIOSSH yeniden dışa verilmiş

/// Mac'e SSH ile bağlanıp interaktif bir PTY (sözde-terminal) açar.
/// Host'tan gelen baytları `onData` ile dışarı verir; kullanıcı girişini `send` ile yollar.
///
/// Citadel'in `withPTY` kapanışı, kanal açık kaldığı sürece çalışır. Kapanış içinde
/// gelen akışı dinleriz; `outbound` writer'ı dışarı saklayıp UI'dan yazma yaparız.
@MainActor
final class SSHTerminalSession: ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case closed
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Host'tan gelen baytlar (TerminalSurface bunu terminale besler). Ana iş parçacığında çağrılır.
    var onData: (([UInt8]) -> Void)?

    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var runTask: Task<Void, Never>?

    /// - initialCommand: bağlanınca shell'e otomatik yazılacak komut (örn. "claude-tmux main").
    /// - password: yalnızca host.auth == .password ise kullanılır.
    func connect(host: Host, password: String,
                 cols: Int, rows: Int, initialCommand: String? = nil) {
        guard case .idle = status else { return }
        status = .connecting

        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                let auth = try SSHAuth.method(for: host, password: password)
                let client = try await SSHClient.connect(
                    host: host.hostname,
                    port: host.port,
                    authenticationMethod: auth,
                    hostKeyValidator: HostKeyVerification.validator(for: host),
                    reconnect: .never
                )
                self.client = client
                self.status = .connected

                let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: cols,
                    terminalRowHeight: rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: SSHTerminalModes([:])
                )

                try await client.withPTY(pty) { inbound, outbound in
                    await MainActor.run { self.writer = outbound }
                    // Shell açılır açılmaz istenen komutu çalıştır (örn. claude-tmux).
                    if let initialCommand {
                        var buf = ByteBufferAllocator().buffer(capacity: initialCommand.utf8.count + 1)
                        buf.writeString(initialCommand + "\n")
                        try await outbound.write(buf)
                    }
                    for try await chunk in inbound {
                        switch chunk {
                        case .stdout(let buffer), .stderr(let buffer):
                            if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) {
                                await MainActor.run { self.onData?(bytes) }
                            }
                        }
                    }
                }
                self.status = .closed
            } catch {
                self.status = .failed(String(describing: error))
            }
        }
    }

    /// Ham bayt gönder (terminal girişi / kontrol dizileri).
    func send(_ data: ArraySlice<UInt8>) {
        guard let writer else { return }
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        Task { try? await writer.write(buffer) }
    }

    func send(text: String) {
        send(ArraySlice(Array(text.utf8)))
    }

    /// Terminal boyutu değişince PTY'ye bildir (programlar doğru sarsın).
    func resize(cols: Int, rows: Int) {
        guard let writer else { return }
        Task { try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0) }
    }

    func disconnect() {
        runTask?.cancel()
        let client = client
        self.client = nil
        self.writer = nil
        if case .failed = status {} else { status = .closed }
        Task { try? await client?.close() }
    }
}
