import SwiftUI

/// Bağlanma rehberi. Önce ev Wi-Fi (basit), sonra dışarıdan erişim (router'da port).
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                introSection
                whatYouNeedSection
                homeWifiSection
                keySection
                remoteSection
            }
            .navigationTitle("Bağlanma Rehberi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
            }
        }
    }

    private var introSection: some View {
        Section {
            Text("İki aşama var: (1) Evdeyken aynı Wi-Fi üzerinden bağlan — en kolayı. (2) Dışarıdayken modemde bir port açıp doğrudan evine bağlan. Aracı/üçüncü uygulama yok; güvenlik için yalnızca SSH anahtarı kullanılır.")
                .font(.callout)
        }
    }

    private var whatYouNeedSection: some View {
        Section("Uygulamaya gireceğin bilgiler") {
            field("1", "Host", "Evde: Mac'in yerel IP'si (Mac'te: ipconfig getifaddr en0). Dışarıda: evinin genel IP'si.")
            field("2", "Port", "Evde 22. Dışarıda modemde açtığın port (ör. 2222).")
            field("3", "Kullanıcı", "Mac kullanıcı adın. (Mac'te: whoami)")
            field("4", "Giriş yöntemi", "SSH Anahtarı (önerilir). Uygulama üretir; bir kez Mac'e eklenir.")
        }
    }

    private var homeWifiSection: some View {
        Section("Aşama 1 — Ev Wi-Fi'sinde (en kolay)") {
            step("1", "Mac'te SSH'ı aç", "System Settings → General → Sharing → Remote Login → AÇIK.")
            step("2", "Telefon ev Wi-Fi'sinde olsun", "Mac ile aynı ağda.")
            step("3", "Mac'in yerel IP'sini öğren", "Mac'te Terminal'de:")
            code("ipconfig getifaddr en0")
            step("4", "Uygulamada Mac ekle", "Host = o IP, Port = 22, Giriş = SSH Anahtarı → Bağlan (Face ID).")
        }
    }

    private var keySection: some View {
        Section("SSH anahtarını Mac'e ekle (tek seferlik)") {
            step("1", "Anahtarı kopyala", "Mac eklerken 'SSH Anahtarı' seçiliyken 'Genel anahtarı kopyala'.")
            step("2", "Mac'e yapıştır", "Mac'te Terminal'de:")
            code(#"mkdir -p ~/.ssh && echo "<anahtar>" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"#)
            note("Özel anahtar telefonda kalır, Face ID ile korunur, asla dışarı çıkmaz. Mac'e yalnızca genel anahtar gider.")
        }
    }

    private var remoteSection: some View {
        Section("Aşama 2 — Dışarıdan erişim (modemde port)") {
            step("1", "Güvenlik kilidi", "Önce anahtarı ekle, sonra Mac'te parola girişini kapat:")
            code("sudo bash mac-setup/bin/harden-ssh.sh")
            step("2", "Modemde port yönlendir", "Modem arayüzü (genelde 192.168.1.1) → Port Forwarding: Dış port (ör. 2222) → Mac'in yerel IP'si : 22.")
            step("3", "Genel IP'ni öğren", "Mac'te Terminal'de:")
            code("curl ifconfig.me")
            step("4", "Uygulamada güncelle", "Host = genel IP, Port = 2222. Mobil veriyle test et.")
            note("Genel IP zamanla değişebilir; değişirse uygulamada güncelle (ya da ücretsiz bir DDNS kur).")
        }
    }

    // MARK: - Yardımcılar

    private func field(_ n: String, _ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "\(n).circle.fill").font(.body.weight(.semibold))
            Text(desc).font(.callout).foregroundStyle(.secondary)
        }.padding(.vertical, 2)
    }

    private func step(_ n: String, _ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n).font(.caption.bold()).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Circle().fill(.tint))
                Text(title).font(.body.weight(.semibold))
            }
            Text(desc).font(.callout).foregroundStyle(.secondary)
        }.padding(.vertical, 2)
    }

    private func code(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }
}
