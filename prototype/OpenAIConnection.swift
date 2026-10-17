import AppKit
import Combine
import CryptoKit
import Foundation
import Network
import Security

enum ReasoningEffort: String, Codable, CaseIterable {
    case modelDefault = "", none, low, medium, high, xhigh, max
    var label: String {
        switch self {
        case .modelDefault: return "Model default"
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra high"
        case .max: return "Max"
        }
    }
}

struct ModelChoice: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    // Explicit model capabilities from official docs, checked October 17, 2026.
    // Unrecognized models keep their server default; never guess effort support.
    var efforts: [ReasoningEffort] {
        switch id {
        case "gpt-6.1-sol", "gpt-6-astra": return [.low, .medium, .high, .xhigh, .max]
        case "gpt-6-sol", "gpt-6-luna": return [.none, .low, .medium, .high, .xhigh, .max]
        default: return [.modelDefault]
        }
    }
    var defaultEffort: ReasoningEffort { efforts.contains(.medium) ? .medium : .modelDefault }
}

struct ChatGPTAccount: Identifiable, Codable {
    var id: String { clientID }
    let clientID: String
    let subject: String
    let email: String
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var expiresAt: Date
    var scopes: [String]
}

struct AccountLabel: Identifiable, Codable {
    let id: String
    let email: String
    let subject: String
    var label: String { "\(email) · \(id.suffix(6))" }
}

enum OpenAIWire {
    static let resource = "https://api.openai.com/v1"
    static let issuer = "https://auth.openai.com"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static func responseBody(model: ModelChoice, effort: ReasoningEffort, input: [[String: Any]],
                             instructions: String, structuredDraft: Bool) throws -> [String: Any] {
        guard model.efforts.contains(effort) else { throw MaieError.message("Choose an effort supported by this model.") }
        var body: [String: Any] = ["model": model.id, "input": input, "instructions": instructions,
                                   "store": false, "stream": true]
        if effort != .modelDefault { body["reasoning"] = ["effort": effort.rawValue] }
        if structuredDraft { body["text"] = DraftResponse.outputFormat }
        return body
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode64(_ text: String) throws -> Data {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { throw MaieError.message("Invalid sign-in token.") }
        return data
    }
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MaieError.message("Could not prepare secure sign-in.")
        }
        return base64URL(Data(bytes))
    }
    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
    static func request(_ path: String, form values: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: issuer + path)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(values)
        request.timeoutInterval = 30
        return request
    }
    static func checked(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MaieError.message("OpenAI returned an invalid response.") }
        guard (200...299).contains(http.statusCode) else {
            // Never expose a raw response, URL, token, or personal prompt in an error.
            switch http.statusCode {
            case 401: throw MaieError.message("OpenAI sign-in expired. Continue with ChatGPT again.")
            case 403: throw MaieError.message("This account or model is not eligible. Check ChatGPT app permissions and usage.")
            case 429: throw MaieError.message("OpenAI usage limit reached. Manage usage in ChatGPT settings or retry later. Your draft is saved.")
            default: throw MaieError.message("OpenAI request failed (HTTP \(http.statusCode)). No billing fallback was used.")
            }
        }
        return data
    }
    static func json(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MaieError.message("OpenAI returned an unexpected response.")
        }
        return value
    }
    static func der(_ tag: UInt8, _ bytes: Data) -> Data {
        var length = bytes.count
        var prefix = Data([tag])
        if length < 128 { prefix.append(UInt8(length)) }
        else {
            var digits: [UInt8] = []
            while length > 0 { digits.insert(UInt8(length & 255), at: 0); length >>= 8 }
            prefix.append(0x80 | UInt8(digits.count)); prefix.append(contentsOf: digits)
        }
        return prefix + bytes
    }
    static func rsaKey(modulus: Data, exponent: Data) throws -> SecKey {
        func integer(_ data: Data) -> Data {
            let bytes = Data(data.drop(while: { $0 == 0 }))
            return der(0x02, (bytes.first ?? 0) >= 128 ? Data([0]) + bytes : bytes)
        }
        let key = der(0x30, integer(modulus) + integer(exponent))
        var error: Unmanaged<CFError>?
        guard let result = SecKeyCreateWithData(key as CFData,
            [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
             kSecAttrKeyClass as String: kSecAttrKeyClassPublic] as CFDictionary, &error) else {
            throw MaieError.message("Could not verify OpenAI identity.")
        }
        return result
    }
    static func validateIDToken(_ token: String, clientID: String, nonce: String) async throws -> [String: Any] {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3 else { throw MaieError.message("Invalid identity token.") }
        let header = try json(decode64(parts[0]))
        guard header["alg"] as? String == "RS256", let kid = header["kid"] as? String else {
            throw MaieError.message("Unsupported identity signature.")
        }
        let jwks = try json(await checked(URLRequest(url: URL(string: issuer + "/.well-known/jwks.json")!)))
        guard let keys = jwks["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              let n = key["n"] as? String, let e = key["e"] as? String else {
            throw MaieError.message("OpenAI identity key was not found.")
        }
        let publicKey = try rsaKey(modulus: decode64(n), exponent: decode64(e))
        let signed = Data("\(parts[0]).\(parts[1])".utf8)
        guard SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
            signed as CFData, try decode64(parts[2]) as CFData, nil) else {
            throw MaieError.message("OpenAI identity signature was rejected.")
        }
        let claims = try json(decode64(parts[1]))
        try validateClaims(claims, clientID: clientID, nonce: nonce)
        return claims
    }
    static func validateClaims(_ claims: [String: Any], clientID: String, nonce: String, now: Date = Date()) throws {
        let audience = (claims["aud"] as? [String]) ?? [claims["aud"] as? String ?? ""]
        guard claims["iss"] as? String == issuer, audience.contains(clientID),
              let exp = claims["exp"] as? Double, exp > now.timeIntervalSince1970,
              claims["nonce"] as? String == nonce,
              let subject = claims["sub"] as? String, !subject.isEmpty,
              audience.count <= 1 || claims["azp"] as? String == clientID else {
            throw MaieError.message("OpenAI identity did not match this sign-in attempt.")
        }
        if let notBefore = claims["nbf"] as? Double, notBefore > now.timeIntervalSince1970 + 30 {
            throw MaieError.message("OpenAI identity is not valid yet.")
        }
    }
}

// A temporary loopback-only listener. No credentials appear in browser success text.
@MainActor final class OAuthCallback {
    private var listener: NWListener?
    private var readiness: CheckedContinuation<Void, Error>?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var outcome: Result<[String: String], Error>?
    private var timeout: Task<Void, Never>?
    private var accepted = false
    var redirectURI = ""
    var expectedState = ""
    func start() async throws {
        try Task.checkCancellation()
        if let outcome { _ = try outcome.get(); return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.receive(connection) }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, Error>) in
                readiness = ready
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, self.outcome == nil else { return }
                        switch state {
                        case .ready:
                            guard let port = listener.port else {
                                self.finish(.failure(MaieError.message("Could not start local sign-in callback."))); return
                            }
                            self.redirectURI = "http://127.0.0.1:\(port.rawValue)/auth/callback"
                            self.readiness?.resume(); self.readiness = nil
                        case .failed:
                            self.finish(.failure(MaieError.message("Could not start local sign-in callback.")))
                        case .cancelled: self.cancel()
                        default: break
                        }
                    }
                }
                listener.start(queue: .main)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
        try Task.checkCancellation()
    }
    func wait(openBrowser: () throws -> Void = {}) async throws -> [String: String] {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let outcome { continuation.resume(with: outcome); return }
                self.continuation = continuation
                timeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 180_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(MaieError.message("Sign-in timed out. Try Continue with ChatGPT again.")))
                }
                // Install the continuation before opening even a fast existing browser login.
                do { try openBrowser() } catch { finish(.failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<[String: String], Error>) {
        guard outcome == nil else { return }
        outcome = result
        switch result {
        case .success: readiness?.resume()
        case .failure(let error): readiness?.resume(throwing: error)
        }
        readiness = nil
        continuation?.resume(with: result); continuation = nil
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
    }
    private func receive(_ connection: NWConnection, buffer: Data = Data()) {
        if buffer.isEmpty { connection.start(queue: .main) }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] bytes, _, complete, error in
            Task { @MainActor in
                guard let self, self.outcome == nil else { connection.cancel(); return }
                let data = buffer + (bytes ?? Data())
                guard data.count <= 16_384, error == nil else { connection.cancel(); return }
                guard let text = String(data: data, encoding: .utf8), text.contains("\r\n\r\n") else {
                    if complete { connection.cancel() } else { self.receive(connection, buffer: data) }; return
                }
                let first = text.components(separatedBy: "\r\n")[0].split(separator: " ")
                var values: [String: String] = [:]
                var valid = first.count == 3 && first[0] == "GET" && !self.accepted
                if valid, let parts = URLComponents(string: "http://127.0.0.1" + first[1]), parts.path == "/auth/callback" {
                    for item in parts.queryItems ?? [] {
                        if values[item.name] != nil { valid = false }
                        values[item.name] = item.value ?? ""
                    }
                    valid = valid && values["state"] == self.expectedState
                } else { valid = false }
                let body = valid ? "Maie received your sign-in. Return to Maie to see the result." : "Invalid callback. Return to Maie and try again."
                let response = "HTTP/1.1 \(valid ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                if valid { self.accepted = true; self.finish(.success(values)) }
            }
        }
    }
}

// Injectable side effects keep lifecycle checks offline and away from real credentials.
struct ConnectionServices {
    var request: (URLRequest) async throws -> Data = OpenAIWire.checked
    var readCredential: (String) throws -> Data? = { try CredentialVault.read(account: $0) }
    var saveCredential: (Data, String) throws -> Void = { try CredentialVault.save($0, account: $1) }
    var deleteCredential: (String) throws -> Void = { try CredentialVault.delete(account: $0) }
}

@MainActor final class OpenAIConnection: ObservableObject {
    @Published var accounts: [AccountLabel] = []
    @Published var selectedAccountID = ""
    @Published var models: [ModelChoice] = []
    @Published var selectedModel = "" {
        didSet {
            if !selectedModel.isEmpty { preferences?.set(selectedModel, forKey: "maie.selectedModel") }
            restoreEffort(); verified = false
        }
    }
    @Published private(set) var selectedEffort: ReasoningEffort = .modelDefault
    @Published var billing = "ChatGPT plan"
    @Published private(set) var authorizationRevision = UUID()
    @Published var status = "Connect your ChatGPT account. No API key required."
    @Published var busy = false
    @Published private(set) var signingIn = false
    @Published var verified = false
    @Published var welcome = false
    private var account: ChatGPTAccount?
    private var callback: OAuthCallback?
    private var refreshTask: (id: UUID, task: Task<ChatGPTAccount, Error>)?
    private var signInTask: Task<Void, Never>?
    private let preferences: UserDefaults?
    private let services: ConnectionServices
    private let labelsURL = LocalStorage.root.appendingPathComponent("accounts.json")
    private let hostURL = LocalStorage.root.appendingPathComponent("host.json")
    var isConnected: Bool { billing == "OpenAI API · separate billing" || account != nil }
    var accountDescription: String { account?.email ?? "Not connected" }
    var currentModel: ModelChoice? { models.first { $0.id == selectedModel } }
    var effortChoices: [ReasoningEffort] { currentModel?.efforts ?? [.modelDefault] }
    private func restoreEffort() {
        let saved = preferences?.string(forKey: "maie.effort." + selectedModel).flatMap(ReasoningEffort.init(rawValue:))
        selectedEffort = saved.flatMap { effortChoices.contains($0) ? $0 : nil } ?? currentModel?.defaultEffort ?? .modelDefault
    }
    func selectEffort(_ effort: ReasoningEffort) {
        guard effortChoices.contains(effort) else { return }
        selectedEffort = effort; verified = false
        preferences?.set(effort.rawValue, forKey: "maie.effort." + selectedModel)
    }
    init(loadSaved: Bool = true, preferences: UserDefaults? = nil, services: ConnectionServices = ConnectionServices()) {
        self.services = services
        self.preferences = preferences ?? (loadSaved ? .standard : nil)
        guard loadSaved else { return }
        accounts = (try? LocalStorage.read([AccountLabel].self, at: labelsURL)) ?? []
        // Reading this app's own Keychain item never reuses another app's session.
        if let id = self.preferences?.string(forKey: "maie.activeAccount"),
           let data = try? services.readCredential(id),
           let saved = try? JSONDecoder().decode(ChatGPTAccount.self, from: data) {
            account = saved; selectedAccountID = id; status = "Connected to ChatGPT."
        }
    }
    func signIn(new: Bool = false) async {
        guard !busy else { return }
        busy = true; signingIn = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSignIn(new: new)
        }
        signInTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        signInTask = nil; signingIn = false; busy = false
    }
    private func performSignIn(new: Bool) async {
        var installed = false
        do {
            try Task.checkCancellation()
            try LocalStorage.directory(LocalStorage.root)
            let host: String
            if let saved = try? LocalStorage.read(String.self, at: hostURL) { host = saved }
            else { host = "urn:uuid:" + UUID().uuidString.lowercased(); try LocalStorage.write(host, to: hostURL) }
            let old: ChatGPTAccount?
            if !new, let data = try services.readCredential(selectedAccountID) {
                old = try JSONDecoder().decode(ChatGPTAccount.self, from: data)
            } else { old = nil }
            let clientID = old?.clientID ?? (new ? nil : accounts.first { $0.id == selectedAccountID }?.id)
            let verifier = try OpenAIWire.random(), state = try OpenAIWire.random(), nonce = try OpenAIWire.random()
            let receiver = OAuthCallback(); callback = receiver; receiver.expectedState = state
            defer { receiver.cancel(); callback = nil }
            try await receiver.start()
            try Task.checkCancellation()
            var values = ["client_id": clientID ?? "dynamic_agent_client", "ext_agent_host_id": host,
                "response_type": "code", "redirect_uri": receiver.redirectURI, "scope": OpenAIWire.scope,
                "resource": OpenAIWire.resource, "state": state, "nonce": nonce,
                "code_challenge_method": "S256", "code_challenge": OpenAIWire.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))]
            if clientID == nil { values["agent_name_hint"] = "Maie" }
            if let old, !old.idToken.isEmpty { values["id_token_hint"] = old.idToken }
            var url = URLComponents(string: OpenAIWire.issuer + "/api/accounts/authorize")!
            url.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
            status = "Complete sign-in in your browser."
            let result = try await receiver.wait {
                guard NSWorkspace.shared.open(url.url!) else { throw MaieError.message("Could not open the sign-in browser.") }
            }
            try Task.checkCancellation()
            guard result["error"] == nil, let code = result["code"], !code.isEmpty else {
                throw MaieError.message("ChatGPT permission was not granted. No API billing was activated.")
            }
            let issued = result["client_id"] ?? clientID ?? ""
            guard !issued.isEmpty, issued != "dynamic_agent_client", clientID == nil || issued == clientID else {
                throw MaieError.message("ChatGPT registration did not return the expected client ID.")
            }
            let token = try OpenAIWire.json(await services.request(OpenAIWire.request("/api/accounts/oauth/token", form: [
                "grant_type": "authorization_code", "client_id": issued, "code": code,
                "code_verifier": verifier, "redirect_uri": receiver.redirectURI, "resource": OpenAIWire.resource])))
            try Task.checkCancellation()
            guard let idToken = token["id_token"] as? String else { throw MaieError.message("Missing identity token.") }
            let claims = try await OpenAIWire.validateIDToken(idToken, clientID: issued, nonce: nonce)
            let subject = claims["sub"] as! String
            let expectedSubject = accounts.first { $0.id == issued }?.subject
            guard expectedSubject == nil || subject == expectedSubject else { throw MaieError.message("The returned account does not match the selected registration.") }
            let saved = try makeAccount(token, clientID: issued, subject: subject, email: claims["email"] as? String ?? "ChatGPT account")
            // No suspension between this final cancellation check and credential installation.
            try Task.checkCancellation()
            try save(saved)
            invalidateAuthorization()
            account = saved; selectedAccountID = issued; billing = "ChatGPT plan"; verified = false
            if !accounts.contains(where: { $0.id == issued }) {
                accounts.append(AccountLabel(id: issued, email: saved.email, subject: subject))
                try LocalStorage.write(accounts, to: labelsURL)
            }
            preferences?.set(issued, forKey: "maie.activeAccount")
            installed = true; signingIn = false
            status = "Using ChatGPT plan. Check models and verify a response."
            if preferences?.bool(forKey: "maie.planWelcome") != true { welcome = true }
            try await loadModels()
        } catch {
            if Task.isCancelled || error is CancellationError {
                status = installed ? "Connected to ChatGPT." : "Sign-in cancelled."
            } else { status = error.localizedDescription }
        }
    }
    private func makeAccount(_ token: [String: Any], clientID: String, subject: String, email: String) throws -> ChatGPTAccount {
        let scopes = (token["scope"] as? String ?? "").split(separator: " ").map(String.init)
        guard scopes.contains("chatgpt.tokens.use.direct"), scopes.contains("resource.invoke"),
              let access = token["access_token"] as? String, !access.isEmpty,
              let refresh = token["refresh_token"] as? String, !refresh.isEmpty,
              let expires = token["expires_in"] as? Double,
              (token["token_type"] as? String)?.lowercased() == "bearer" else {
            throw MaieError.message("ChatGPT plan usage was not granted. Check your eligible plan and app permissions.")
        }
        return ChatGPTAccount(clientID: clientID, subject: subject, email: email,
            accessToken: access, refreshToken: refresh, idToken: token["id_token"] as? String ?? "",
            expiresAt: Date().addingTimeInterval(expires), scopes: scopes)
    }
    private func invalidateAuthorization() {
        authorizationRevision = UUID()
        refreshTask?.task.cancel()
        refreshTask = nil
    }
    private func save(_ value: ChatGPTAccount) throws { try services.saveCredential(JSONEncoder().encode(value), value.clientID) }
    private func bearer() async throws -> String {
        if billing == "OpenAI API · separate billing" {
            guard let key = try services.readCredential("optional-api-key"), let text = String(data: key, encoding: .utf8) else {
                throw MaieError.message("No optional API key configured.")
            }; return text
        }
        guard let current = account else { throw MaieError.message("Continue with ChatGPT first.") }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        if let refreshTask { return try await refreshTask.task.value.accessToken }
        let revision = authorizationRevision, refreshID = UUID()
        let task = Task { () throws -> ChatGPTAccount in
            let token = try OpenAIWire.json(await services.request(OpenAIWire.request("/api/accounts/oauth/token", form: [
                "grant_type": "refresh_token", "client_id": current.clientID,
                "refresh_token": current.refreshToken, "resource": OpenAIWire.resource])))
            var updated = try makeAccount(token, clientID: current.clientID, subject: current.subject, email: current.email)
            if updated.idToken.isEmpty { updated.idToken = current.idToken }
            try Task.checkCancellation()
            guard authorizationRevision == revision, account?.clientID == current.clientID,
                  account?.subject == current.subject else {
                throw MaieError.message("Connection changed. Review your request again.")
            }
            // No suspension between validation and installation of rotating credentials.
            try save(updated); account = updated
            return updated
        }
        refreshTask = (refreshID, task)
        defer { if refreshTask?.id == refreshID { refreshTask = nil } }
        return try await task.value.accessToken
    }
    func loadModels() async throws {
        var request = URLRequest(url: URL(string: OpenAIWire.resource + "/models")!)
        request.setValue("Bearer \(try await bearer())", forHTTPHeaderField: "Authorization")
        let value = try OpenAIWire.json(await services.request(request))
        if billing == "ChatGPT plan" {
            models = (value["models"] as? [[String: Any]] ?? []).compactMap {
                guard $0["visibility"] as? String == "list", let slug = $0["slug"] as? String,
                      let name = $0["display_name"] as? String else { return nil }
                return ModelChoice(id: slug, name: name)
            }
        } else {
            models = (value["data"] as? [[String: Any]] ?? []).compactMap {
                guard let id = $0["id"] as? String, id.hasPrefix("gpt-") else { return nil }
                return ModelChoice(id: id, name: id)
            }.sorted { $0.id < $1.id }
        }
        let preferred = preferences?.string(forKey: "maie.selectedModel") ?? selectedModel
        selectedModel = models.first { $0.id == preferred }?.id ?? models.first { $0.id == "gpt-6.1-sol" }?.id ?? models.first?.id ?? ""
        verified = false
        guard !models.isEmpty else { throw MaieError.message("No eligible models returned for this connection.") }
        status = "Models updated."
    }
    func refreshModels() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await loadModels() } catch { status = error.localizedDescription }
    }
    func restoreModels() async {
        guard account != nil, models.isEmpty, !busy else { return }
        await refreshModels()
    }
    func useAPIKey(_ key: String) async {
        guard !busy, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            try services.saveCredential(Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8), "optional-api-key")
            invalidateAuthorization()
            billing = "OpenAI API · separate billing"; models = []; verified = false
            try await loadModels()
        } catch { status = error.localizedDescription }
    }
    func useChatGPT() {
        invalidateAuthorization()
        billing = "ChatGPT plan"; models = []; selectedModel = ""; verified = false
    }
    func forgetAPIKey() {
        guard !busy else { return }
        do {
            try services.deleteCredential("optional-api-key")
            useChatGPT(); status = "Optional API key removed. ChatGPT plan selected."
        } catch { status = error.localizedDescription }
    }
    func verify() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        verified = false
        do {
            let text = try await respond(input: [["role": "user", "content": "Say exactly: Maie connection verified."]], instructions: "Follow the user's exact output request.")
            verified = true; status = "Completed response from \(selectedModel): \(text)"
        } catch { status = error.localizedDescription }
    }
    func respond(input: [[String: Any]], instructions: String, structuredDraft: Bool = false,
                 model: String? = nil, effort: ReasoningEffort? = nil,
                 authorizationRevision expectedRevision: UUID? = nil) async throws -> String {
        if let expectedRevision, expectedRevision != authorizationRevision {
            throw MaieError.message("Connection changed. Review your request again.")
        }
        guard let choice = models.first(where: { $0.id == (model ?? selectedModel) }) else {
            throw MaieError.message("Choose an available model first.")
        }
        let body = try OpenAIWire.responseBody(model: choice, effort: effort ?? selectedEffort,
            input: input, instructions: instructions, structuredDraft: structuredDraft)
        var request = URLRequest(url: URL(string: OpenAIWire.resource + "/responses")!)
        request.httpMethod = "POST"; request.timeoutInterval = 120
        let token = try await bearer()
        try Task.checkCancellation()
        if let expectedRevision, expectedRevision != authorizationRevision {
            throw MaieError.message("Connection changed. Review your request again.")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw MaieError.message("Invalid OpenAI response.") }
        guard http.statusCode == 200 else {
            let message = http.statusCode == 429 ? "OpenAI usage limit reached. Manage usage in ChatGPT settings. Your draft is saved." : "OpenAI request failed (HTTP \(http.statusCode)). Check account permissions. No billing fallback was used."
            throw MaieError.message(message)
        }
        var stream = ResponseStream()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("data:") { try stream.consume(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }
        let text = try stream.result()
        verified = true
        return text
    }
    func signOut() async {
        if billing == "OpenAI API · separate billing" { forgetAPIKey(); return }
        guard !busy else { return }; busy = true; defer { busy = false }
        invalidateAuthorization()
        callback?.cancel()
        guard let old = account else { useChatGPT(); return }
        var revoked = false
        for attempt in 0..<3 {
            do {
                _ = try await services.request(OpenAIWire.request("/api/accounts/oauth/revoke", form: [
                    "client_id": old.clientID, "token": old.refreshToken, "token_type_hint": "refresh_token"]))
                revoked = true; break
            } catch {
                if attempt < 2 { try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000) }
            }
        }
        do { try services.deleteCredential(old.clientID) }
        catch { status = error.localizedDescription; return }
        account = nil; useChatGPT(); preferences?.removeObject(forKey: "maie.activeAccount")
        status = revoked ? "Signed out. Registration retained for a later sign-in." : "Signed out locally. Remote revocation was not confirmed; disconnect Maie in ChatGPT settings."
    }
    func dismissWelcome() { welcome = false; preferences?.set(true, forKey: "maie.planWelcome") }
    func cancelSignIn() {
        guard signingIn else { return }
        signInTask?.cancel(); callback?.cancel()
    }
}

struct ResponseStream {
    private(set) var text = ""
    private(set) var completed = false
    private var failed = false
    mutating func consume(_ data: String) throws {
        if data == "[DONE]" { return }
        let event = try OpenAIWire.json(Data(data.utf8))
        switch event["type"] as? String {
        case "response.output_text.delta":
            text += event["delta"] as? String ?? ""
            if text.utf8.count > 262_144 { throw MaieError.message("Model response exceeded the prototype limit.") }
        case "response.completed":
            guard let response = event["response"] as? [String: Any], response["status"] as? String == "completed" else {
                failed = true; return
            }
            completed = true
        case "response.failed", "response.incomplete", "error": failed = true
        default: break
        }
    }
    func result() throws -> String {
        guard completed, !failed, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MaieError.message("OpenAI did not complete a response. Your draft is unchanged; retry when ready.")
        }
        return text
    }
}
