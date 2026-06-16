import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLock.enabledKey) private var appLockEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Uygulama kilidi (Face ID)", isOn: $appLockEnabled)
                } footer: {
                    Text("Açıkken, uygulama her açılışta ve arka plandan dönüşte Face ID / cihaz parolası ister. Telefonun açıkken bile kayıtlı Mac'lerin korunur.")
                }

                Section("Güvenlik") {
                    row("lock.shield", "Yalnızca SSH anahtarı", "Parola yok; kaba-kuvvet saldırısı imkânsız.")
                    row("key.fill", "Anahtar cihazda + Face ID", "Özel anahtar Keychain'de, Face ID arkasında; telefondan çıkmaz.")
                    row("checkmark.shield", "Host doğrulama (TOFU)", "İlk bağlantıda Mac'in kimliği sabitlenir; değişirse bağlantı reddedilir (MITM koruması).")
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
            }
        }
    }

    private func row(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.green).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
