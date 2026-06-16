import SwiftUI
import LocalAuthentication

/// Uygulama açılışında ve arka plandan dönüşte Face ID / parola kilidi.
/// Telefon kilitsizken bile uygulamanın (kayıtlı Mac'ler, oturumlar) açılmasını engeller.
@MainActor
final class AppLock: ObservableObject {
    @Published var unlocked = false
    static let enabledKey = "app_lock_enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true   // varsayılan: AÇIK
    }

    func authenticate() {
        guard Self.isEnabled else { unlocked = true; return }
        let ctx = LAContext()
        var err: NSError?
        // Biyometri yoksa cihaz parolasına düşer. Hiçbiri yoksa kilitleyip kullanıcıyı dışarıda bırakma.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            unlocked = true; return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "ClaudeRemote'u açmak için kimliğini doğrula") { ok, _ in
            Task { @MainActor in self.unlocked = ok }
        }
    }

    func lock() { unlocked = false }
}

/// İçeriği kilit arkasına alan sarmalayıcı.
struct AppLockGate<Content: View>: View {
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var phase
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            if lock.unlocked {
                content()
            } else {
                LockScreen { lock.authenticate() }
            }
        }
        .onAppear { lock.authenticate() }
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .active:     if !lock.unlocked { lock.authenticate() }
            case .background: lock.lock()        // arka plana geçince tekrar kilitle
            default: break
            }
        }
    }
}

private struct LockScreen: View {
    let retry: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("ClaudeRemote kilitli").font(.headline)
                Button("Kilidi aç", action: retry).buttonStyle(.borderedProminent)
            }
        }
    }
}
