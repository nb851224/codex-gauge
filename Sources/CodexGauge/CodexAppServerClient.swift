import Foundation
import CFNetwork
import OSLog

struct UsageLimitWindow: Equatable, Identifiable {
    let usedPercent: Int
    let resetsAt: Date
    let durationMinutes: Int

    var id: String {
        "\(durationMinutes)-\(Int(resetsAt.timeIntervalSince1970))"
    }
}

struct RateLimitSnapshot {
    let windows: [UsageLimitWindow]
    let planType: String?
    let resetCredits: ResetCreditsSummary?

    var mainWindow: UsageLimitWindow {
        windows.max(by: { $0.durationMinutes < $1.durationMinutes })!
    }

    var shortWindow: UsageLimitWindow? {
        guard windows.count > 1 else { return nil }
        return windows.min(by: { $0.durationMinutes < $1.durationMinutes })
    }

    var usedPercent: Int { mainWindow.usedPercent }
    var resetsAt: Date { mainWindow.resetsAt }
    var windowDurationMinutes: Int { mainWindow.durationMinutes }
}

struct ResetCredit: Identifiable, Equatable {
    let id: String
    let title: String?
    let description: String?
    let expiresAt: Date?
}

struct ResetCreditsSummary: Equatable {
    let availableCount: Int
    let credits: [ResetCredit]
}

final class CodexAppServerClient {
    var onSnapshot: ((RateLimitSnapshot) -> Void)?
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "CodexGauge.AppServer")
    private let logger = Logger(subsystem: "com.eric.codex-gauge", category: "app-server")
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputBuffer = Data()
    private var nextRequestID = 1
    private var responseHandlers: [Int: ([String: Any]) -> Void] = [:]
    private var refreshPending = false
    private var initialized = false
    private var generation = 0
    private var requestTimeouts: [Int: DispatchWorkItem] = [:]

    private let executableURL: URL
    private let arguments: [String]
    private let requestTimeout: TimeInterval

    init(executableURL: URL = URL(fileURLWithPath: "/bin/zsh"),
         arguments: [String] = ["-lc", """
         if [[ -n ${CODEX_GAUGE_HTTP_PROXY:-} ]]; then
             export HTTP_PROXY="$CODEX_GAUGE_HTTP_PROXY" http_proxy="$CODEX_GAUGE_HTTP_PROXY"
         fi
         if [[ -n ${CODEX_GAUGE_HTTPS_PROXY:-} ]]; then
             export HTTPS_PROXY="$CODEX_GAUGE_HTTPS_PROXY" https_proxy="$CODEX_GAUGE_HTTPS_PROXY"
         fi
         exec codex app-server --stdio
         """],
         requestTimeout: TimeInterval = 30) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.requestTimeout = requestTimeout
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.process?.isRunning != true else { return }
            self.launch()
        }
    }

    func refresh() {
        queue.async { [weak self] in
            self?.requestRateLimits()
        }
    }

    func stop() {
        queue.sync {
            disconnect()
        }
    }

    // Run only on queue. Invalidate callbacks before terminating the old connection.
    private func disconnect() {
        generation += 1
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        try? inputPipe?.fileHandleForWriting.close()
        process?.terminate()
        process = nil
        inputPipe = nil
        initialized = false
        refreshPending = false
        responseHandlers.removeAll()
        requestTimeouts.values.forEach { $0.cancel() }
        requestTimeouts.removeAll()
        outputBuffer.removeAll()
    }

    private func launch() {
        disconnect()
        let connectionGeneration = generation
        logger.info("Launching Codex app server")
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = Self.systemProxyEnvironment()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                guard let self, self.generation == connectionGeneration else { return }
                self.consume(data)
            }
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard
                !data.isEmpty,
                let message = String(data: data, encoding: .utf8)
            else { return }
            self?.logger.error("Codex app server stderr: \(message, privacy: .public)")
        }
        process.terminationHandler = { [weak self] _ in
            self?.queue.async {
                guard let self, self.generation == connectionGeneration else { return }
                self.disconnect()
                self.reportError(L10n.text("client_disconnected"))
            }
        }

        do {
            try process.run()
            self.process = process
            self.inputPipe = input
            logger.info("Codex app server launched, pid=\(process.processIdentifier, privacy: .public)")
            initialize()
        } catch {
            logger.error("Failed to launch Codex app server: \(error.localizedDescription, privacy: .public)")
            reportError(L10n.text("client_launch_failed"))
        }
    }

    // Login shell profiles can contain a retired proxy. Apply the active macOS
    // proxy after the profile has run, without changing the user's shell settings.
    private static func systemProxyEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CODEX_GAUGE_HTTP_PROXY")
        environment.removeValue(forKey: "CODEX_GAUGE_HTTPS_PROXY")
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]
        else { return environment }
        for (scheme, enabledKey, hostKey, portKey) in [
            ("HTTP", kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesHTTPProxy, kCFNetworkProxiesHTTPPort),
            ("HTTPS", kCFNetworkProxiesHTTPSEnable, kCFNetworkProxiesHTTPSProxy, kCFNetworkProxiesHTTPSPort)
        ] {
            guard (settings[enabledKey as String] as? NSNumber)?.boolValue == true,
                  let host = settings[hostKey as String] as? String,
                  let port = settings[portKey as String] as? NSNumber,
                  !host.isEmpty, (1...65535).contains(port.intValue) else { continue }
            var url = URLComponents()
            url.scheme = "http"
            url.host = host
            url.port = port.intValue
            environment["CODEX_GAUGE_\(scheme)_PROXY"] = url.string
        }
        return environment
    }

    private func initialize() {
        sendRequest(
            method: "initialize",
            params: [
                "clientInfo": ["name": "codex-gauge", "version": "0.2.8"],
                "capabilities": ["experimentalApi": true]
            ]
        ) { [weak self] response in
            guard let self else { return }
            guard response["result"] != nil, response["error"] == nil else {
                self.disconnect()
                self.reportError(L10n.text("client_disconnected"))
                return
            }
            self.initialized = true
            self.logger.info("Codex app server initialized")
            self.sendNotification(method: "initialized")
            self.requestRateLimits()
        }
    }

    private func requestRateLimits() {
        guard process?.isRunning == true else {
            start()
            return
        }
        guard initialized, !refreshPending else { return }
        refreshPending = true
        logger.info("Requesting account rate limits")

        sendRequest(method: "account/rateLimits/read", params: NSNull()) { [weak self] response in
            guard let self else { return }
            self.refreshPending = false
            guard
                let result = response["result"] as? [String: Any],
                let snapshot = Self.parseSnapshot(result)
            else {
                let error = String(describing: response["error"] ?? "none")
                self.logger.error("Unable to parse account rate-limit response; error=\(error, privacy: .public)")
                self.disconnect()
                self.reportError(L10n.text("client_usage_unavailable"))
                return
            }
            self.logger.info(
                "Received rate limits: used=\(snapshot.usedPercent, privacy: .public), window=\(snapshot.windowDurationMinutes, privacy: .public), plan=\(snapshot.planType ?? "unknown", privacy: .public)"
            )
            DispatchQueue.main.async { [weak self] in
                self?.onSnapshot?(snapshot)
            }
        }
    }

    static func parseSnapshot(_ result: [String: Any]) -> RateLimitSnapshot? {
        var candidates: [[String: Any]] = []
        if
            let buckets = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = buckets["codex"] as? [String: Any]
        {
            candidates.append(codex)
        }
        if let legacy = result["rateLimits"] as? [String: Any] {
            candidates.append(legacy)
        }

        for bucket in candidates {
            let windows = ["primary", "secondary"].compactMap { key in
                parseWindow(bucket[key])
            }
            guard !windows.isEmpty else { continue }

            return RateLimitSnapshot(
                windows: windows,
                planType: bucket["planType"] as? String,
                resetCredits: parseResetCredits(result["rateLimitResetCredits"])
            )
        }
        return nil
    }

    private static func parseWindow(_ value: Any?) -> UsageLimitWindow? {
        guard
            let object = value as? [String: Any],
            let used = number(object["usedPercent"]),
            let resetTimestamp = number(object["resetsAt"]),
            let duration = number(object["windowDurationMins"]),
            duration > 0
        else { return nil }

        return UsageLimitWindow(
            usedPercent: min(100, max(0, used)),
            resetsAt: Date(timeIntervalSince1970: TimeInterval(resetTimestamp)),
            durationMinutes: duration
        )
    }

    private static func number(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let integer = value as? Int { return integer }
        if let double = value as? Double { return Int(double.rounded()) }
        return nil
    }

    private static func parseResetCredits(_ value: Any?) -> ResetCreditsSummary? {
        guard
            let object = value as? [String: Any],
            let count = number(object["availableCount"])
        else { return nil }

        let rawCredits = object["credits"] as? [[String: Any]] ?? []
        let credits = rawCredits.compactMap { item -> ResetCredit? in
            guard
                let id = item["id"] as? String,
                (item["status"] as? String) == "available"
            else { return nil }

            let expiresAt = number(item["expiresAt"]).map {
                Date(timeIntervalSince1970: TimeInterval($0))
            }
            return ResetCredit(
                id: id,
                title: item["title"] as? String,
                description: item["description"] as? String,
                expiresAt: expiresAt
            )
        }

        return ResetCreditsSummary(
            availableCount: max(0, count),
            credits: credits
        )
    }

    private func sendRequest(method: String, params: Any, completion: @escaping ([String: Any]) -> Void) {
        let id = nextRequestID
        nextRequestID += 1
        responseHandlers[id] = completion
        let connectionGeneration = generation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == connectionGeneration,
                  self.responseHandlers[id] != nil else { return }
            self.logger.error("App server request timed out: \(method, privacy: .public)")
            self.disconnect()
            self.reportError(L10n.text("client_disconnected"))
        }
        requestTimeouts[id] = timeout
        queue.asyncAfter(deadline: .now() + requestTimeout, execute: timeout)
        send(["id": id, "method": method, "params": params])
    }

    private func sendNotification(method: String) {
        send(["method": method])
    }

    private func send(_ object: [String: Any]) {
        guard
            let inputPipe,
            JSONSerialization.isValidJSONObject(object),
            var data = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        data.append(0x0A)
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            disconnect()
            reportError(L10n.text("client_disconnected"))
        }
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard
                !line.isEmpty,
                let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            handle(object)
        }
    }

    private func handle(_ object: [String: Any]) {
        if let id = (object["id"] as? NSNumber)?.intValue,
           let handler = responseHandlers.removeValue(forKey: id) {
            requestTimeouts.removeValue(forKey: id)?.cancel()
            handler(object)
            return
        }

        if object["method"] as? String == "account/rateLimits/updated" {
            requestRateLimits()
        }
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(message)
        }
    }

    deinit {
        process?.terminate()
    }
}
