// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LiveAssistant", platforms: [.macOS(.v14)], products: [.executable(name: "LiveAssistant", targets: ["Assistant"])], dependencies: [.package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.1.1")], targets: [
    .target(name: "AssistantCore"),
    .executableTarget(name: "Assistant", dependencies: ["AssistantCore", .product(name: "SocketIO", package: "socket.io-client-swift")], exclude: ["Resources/AppIcon.icns"], resources: [.process("Resources")]),
    .testTarget(name: "AssistantCoreTests", dependencies: ["AssistantCore"]),
    .testTarget(name: "AssistantIntegrationTests", dependencies: ["Assistant"])
])
