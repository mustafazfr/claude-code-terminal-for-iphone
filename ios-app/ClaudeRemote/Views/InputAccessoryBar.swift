import SwiftUI

/// Mobil klavyede olmayan tuşlar için yatay kısayol çubuğu.
/// Baytları doğrudan SSH'a yollar (uzak uç yankılar).
struct InputAccessoryBar: View {
    let session: SSHTerminalSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                key("esc")    { session.send(ArraySlice([0x1b])) }
                key("tab")    { session.send(ArraySlice([0x09])) }
                key("^C")     { session.send(ArraySlice([0x03])) }
                key("^D")     { session.send(ArraySlice([0x04])) }
                key("^L")     { session.send(ArraySlice([0x0c])) }
                key("↑")      { session.send(ArraySlice([0x1b, 0x5b, 0x41])) }
                key("↓")      { session.send(ArraySlice([0x1b, 0x5b, 0x42])) }
                key("←")      { session.send(ArraySlice([0x1b, 0x5b, 0x44])) }
                key("→")      { session.send(ArraySlice([0x1b, 0x5b, 0x43])) }
                key("|")      { session.send(text: "|") }
                key("~")      { session.send(text: "~") }
                key("/")      { session.send(text: "/") }
                key("-")      { session.send(text: "-") }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
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
