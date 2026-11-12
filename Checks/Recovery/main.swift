import Foundation

enum L10n { static func text(_ key: String) -> String { key } }
let state = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: state) }
let client = CodexAppServerClient(
    executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
    arguments: [CommandLine.arguments[1], state.path], requestTimeout: 1)
var failures = 0
var received = false
client.onError = { _ in
    failures += 1
    client.refresh()
}
client.onSnapshot = { snapshot in
    precondition(snapshot.usedPercent == 17)
    received = true
}
client.start()
let deadline = Date().addingTimeInterval(12)
while !received && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
client.stop()
precondition(received, "Refresh must recover after two hung connections")
precondition(failures == 2, "Both handshake and usage timeouts must report failure")
precondition((try! String(contentsOf: state, encoding: .utf8)) == "3")
print("PASS: handshake timeout, usage timeout, reconnect and fresh snapshot")
