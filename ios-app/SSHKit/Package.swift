// swift-tools-version:5.9
import PackageDescription

// SSHKit: tüm SSH/terminal bağımlılıklarını tek bir yerel pakette toplar.
// Uygulama yalnızca SSHKit'e bağlanır; böylece SPM transitif grafiği (Citadel'in
// swift-crypto/_CryptoExtras/SwiftASN1, nio-ssh fork vb.) doğal biçimde çözer.
// SSHKit, gerekli modülleri @_exported ile yeniden dışa verir (bkz. Exports.swift).
let package = Package(
    name: "SSHKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SSHKit", targets: ["SSHKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel", from: "0.12.1"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3"),
    ],
    targets: [
        .target(
            name: "SSHKit",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
    ]
)
