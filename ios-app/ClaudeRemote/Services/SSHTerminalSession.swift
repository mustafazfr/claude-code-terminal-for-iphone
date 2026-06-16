import Foundation
import SSHKit   // Citadel + NIOCore + NIOSSH yeniden dışa verilmiş

/// NIO event-loop thread'inden gelen baytları kilitle koruyup biriktirir.
/// MainActor'a her chunk için zıplamak yerine, ~60fps'de topluca boşaltırız (coalescing) —
/// yoğun çıktıda (Claude'un TUI'si) takılma ve giriş gecikmesini önler.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []
    func append(_ b: [UInt8]) { lock.lock(); bytes.append(contentsOf: b); lock.unlock() }
    func drain() -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        let out = bytes; bytes.removeAll(keepingCapacity: true); return out
    }
}

/// Mac'e SSH ile bağlanıp interaktif bir PTY açar. Host çıktısını `onData` ile (MainActor'da,
/// tamponlanmış) verir; kullanıcı girişini `send` ile yollar.
@MainActor
final class SSHTerminalSession: ObservableObject {
    enum Status: Equatable {
        case idle, connecting, connected, closed
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Host'tan gelen baytlar (TerminalSurface terminale besler). MainActor'da, ~16ms'de bir, toplu.
    var onData: (([UInt8]) -> Void)?

    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var runTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private nonisolated let outBuf = OutputBuffer()

    func connect(host: Host, password: String,
                 cols: Int, rows: Int, initialCommand: String? = nil) {
        guard case .idle = status else { return }
        status = .connecting
        startFlushLoop()

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
                    if let initialCommand {
                        var buf = ByteBufferAllocator().buffer(capacity: initialCommand.utf8.count + 1)
                        buf.writeString(initialCommand + "\n")
                        try await outbound.write(buf)
                    }
                    // Sıcak yol: MainActor'a zıplamadan tampona yaz (flush döngüsü boşaltır).
                    for try await chunk in inbound {
                        switch chunk {
                        case .stdout(let buffer), .stderr(let buffer):
                            if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) {
                                self.outBuf.append(bytes)
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

    /// ~16ms'de bir tamponu boşaltıp terminale besler (60fps). Tek MainActor akışı.
    private func startFlushLoop() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard let self else { return }
                let data = self.outBuf.drain()
                if !data.isEmpty { self.onData?(data) }
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

    func send(text: String) { send(ArraySlice(Array(text.utf8))) }

    func resize(cols: Int, rows: Int) {
        guard let writer else { return }
        Task { try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0) }
    }

    func disconnect() {
        runTask?.cancel()
        flushTask?.cancel()
        let client = client
        self.client = nil
        self.writer = nil
        if case .failed = status {} else { status = .closed }
        Task { try? await client?.close() }
    }
}
