import SwiftUI

/// Host açılınca İLK ekran: host anahtarı doğrulanana kadar oturum listesini göstermez.
/// - Zaten sabitliyse anında geçer.
/// - İlk kez ise parmak izini gösterir; kullanıcı Mac'le karşılaştırıp onaylar (MITM koruması).
struct HostGateView: View {
    let host: Host
    let password: String

    @StateObject private var verifier = HostVerifier()

    var body: some View {
        Group {
            switch verifier.state {
            case .verified:
                SessionListView(host: host, password: password)

            case .needsApproval(let fingerprint):
                approval(fingerprint)

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.red)
                    Text("Bağlanılamadı").font(.headline)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    Button("Tekrar dene") { Task { await verifier.start(host: host, password: password) } }
                        .buttonStyle(.borderedProminent)
                }.padding()

            case .idle, .probing:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Mac'in kimliği doğrulanıyor…").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await verifier.start(host: host, password: password) }
    }

    private func approval(_ fingerprint: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("İlk bağlantı — Mac'in kimliğini doğrula", systemImage: "checkmark.shield")
                    .font(.headline)

                Text("Bu Mac'e ilk kez bağlanıyorsun. Ortadaki-adam saldırısına karşı, aşağıdaki parmak izinin gerçekten senin Mac'ine ait olduğunu doğrula.")
                    .font(.callout).foregroundStyle(.secondary)

                Text(fingerprint)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Mac'te doğrula:").font(.callout.weight(.medium))
                    Text("Mac'te bir terminalde şunu çalıştır ve çıkan parmak izinin yukarıdakiyle AYNI olduğunu gör:")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("claude-doctor --fingerprint")
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Text("Eşleşmiyorsa BAĞLANMA — biri araya girmiş olabilir.")
                    .font(.caption).foregroundStyle(.red)

                Button {
                    verifier.approve(host: host)
                } label: {
                    Label("Eşleşiyor, güven ve bağlan", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
