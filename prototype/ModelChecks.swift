import Foundation
import Security

@main struct ModelChecks {
    @MainActor static func main() async throws {
        try checkQuestionSets()
        try await checkQuestionTaskRouting()
        if CommandLine.arguments.contains("--questions-only") { return }
        try await checkRefreshLifecycle()
        try await checkReplacementTask()
        if CommandLine.arguments.contains("--refresh-only") { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maie-state-checks-" + UUID().uuidString)
        setenv("MAIE_DATA_DIR", root.path, 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = OpenAIConnection(loadSaved: false)
        let store = SessionStore(connection: connection, modelResponder: { _ in
            preconditionFailure("A preview-only check attempted a model request")
        })
        try store.start()
        defer { store.stop() }
        let lease = try LocalStorage.read(ServiceLease.self, at: HookFiles.lease)
        let secondInstance = SessionStore(connection: connection)
        do { try secondInstance.start(); preconditionFailure("Two service instances were allowed") } catch { }
        secondInstance.stop()
        let unchangedLease = try LocalStorage.read(ServiceLease.self, at: HookFiles.lease)
        precondition(unchangedLease.runID == lease.runID, "A failed second instance must not remove the first service lease")
        // Preserve multilingual and shell-character coverage in English source.
        let exact = "  \u{0397} \u{03b4}\u{03b9}\u{03ba}\u{03ae} \u{03bc}\u{03bf}\u{03c5} \u{03c6}\u{03c1}\u{03ac}\u{03c3}\u{03b7}.\n\u{0395}\u{03bb}\u{03bb}\u{03b7}\u{03bd}\u{03b9}\u{03ba}\u{03ac}, \"quotes\", $(literal) 🫧\n"
        func incoming(_ session: String, _ tool: String) throws -> HookEnvelope {
            let id = UUID()
            let payload: [String: Any] = ["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion",
                "session_id": session, "tool_use_id": tool, "cwd": "/tmp/fictional-project",
                "tool_input": ["questions": [["question": "Where should preferences live?", "multiSelect": false,
                    "options": [["label": "Local", "description": "On this Mac"], ["label": "Sync", "description": "Across devices"]]]]]]
            try LocalStorage.directory(HookFiles.folder(id))
            try LocalStorage.write(Date(), to: HookFiles.file(id, "heartbeat.json"))
            return HookEnvelope(id: id, runID: lease.runID, pid: getpid(), created: Date(), timeout: 1_800,
                payload: try JSONSerialization.data(withJSONObject: payload))
        }
        let a = try incoming("session-a", "tool-a")
        let b = try incoming("session-b", "tool-b")
        try store.ingest(a)
        precondition(!store.canSubmit)
        store.setDraft(exact); store.setComposer("Explain local preferences")
        try store.ingest(b)
        precondition(store.activeRequestID == a.id, "Incoming question must not steal focus")
        store.selectSession("session-b")
        precondition(store.activeRequest?.draft == "")
        store.setDraft("Second answer")
        store.selectSession("session-a")
        precondition(store.activeRequest?.draft == exact)
        store.prepare(.discuss)
        precondition(store.preview == nil, "No network preview before a connection and model are selected")
        connection.models = [ModelChoice(id: "gpt-6.1-sol", name: "GPT-6.1 Sol")]
        connection.selectedModel = "gpt-6.1-sol"; connection.verified = true
        // Simulate an explicitly selected billing route for preview-only checks, without a key or network.
        connection.billing = "OpenAI API · separate billing"
        store.prepare(.discuss)
        precondition(store.preview?.text.contains(exact) == true)
        precondition(store.activeRequest?.draft == exact && store.activeRequest?.status == .waiting)
        precondition(store.activeSession?.messages.isEmpty == true, "Preview must not call OpenAI or record a sent message")
        let discussionPreview = store.preview!
        let discussionBody = try OpenAIWire.responseBody(model: connection.currentModel!, effort: discussionPreview.effort,
            input: discussionPreview.input, instructions: discussionPreview.instructions, structuredDraft: false)
        precondition(discussionPreview.text.contains(discussionBody["instructions"] as! String),
            "All discussion guidance sent to the model must be visible in the approved preview")
        let skillRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("skills")
        for (name, compiled) in [("wait-what", DiscussionGuidance.explain), ("teach", DiscussionGuidance.teach)] {
            let file = skillRoot.appendingPathComponent(name).appendingPathComponent("SKILL.md")
            let text = try String(contentsOf: file, encoding: .utf8)
            let body = text.components(separatedBy: "\n---\n").dropFirst().joined(separator: "\n---\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            precondition(compiled == body, "The compiled skill must match its reviewed SKILL.md body exactly")
            precondition(discussionPreview.instructions.contains(compiled),
                "The actual discussion request must include the reviewed skill body")
        }
        do {
            store.prepare(.suggest)
            precondition(store.preview?.instructions.contains(DraftResponse.instruction) == true)
            precondition(store.preview?.instructions.contains(DiscussionGuidance.instructions) == false,
                "Teaching guidance must not turn a structured draft action into a lesson")
            precondition(store.activeRequest?.draft == exact && store.activeSession?.messages.isEmpty == true)
            precondition(store.preview?.action == .suggest,
                "A draft alone must support suggesting an answer")
        }
        store.prepare(.discuss)
        precondition(store.preview?.effort == .medium)
        connection.selectEffort(.high)
        store.sendPreview()
        precondition(store.preview == nil && store.activeSession?.messages.isEmpty == true,
            "An effort change after preview must block sending until reviewed again")
        precondition(!store.busySessionIDs.contains("session-a"))
        connection.selectEffort(.medium)
        store.setComposer("Changed message")
        precondition(store.preview == nil)
        let proposal = try DraftResponse.parse(#"{"kind":"proposal","text":"A suggested answer"}"#)
        store.applyDraftResponse(proposal, sessionID: "session-a", requestID: a.id)
        precondition(store.activeRequest?.proposal == "A suggested answer" && store.activeRequest?.draft == exact)
        precondition(store.activeSession?.discussionMessages.contains(where: { $0.text == "A suggested answer" }) == false,
            "A proposal must appear once in its separate review area")
        let clarification = try DraftResponse.parse(#"{"kind":"clarification","text":"Which device do you use?"}"#)
        store.applyDraftResponse(clarification, sessionID: "session-a", requestID: a.id)
        precondition(store.activeRequest?.proposal == nil && store.activeRequest?.draft == exact)
        precondition(store.activeSession?.discussionMessages.last?.text == "Which device do you use?",
            "Clarifications belong in discussion, never in the answer proposal")
        do { _ = try DraftResponse.parse(#"{"kind":"unknown","text":"Bad result"}"#); preconditionFailure("Unknown response type accepted") } catch { }
        do { _ = try DraftResponse.parse(#"{"kind":"proposal","text":" "}"#); preconditionFailure("Empty proposal accepted") } catch { }
        store.submit()
        let decision = try LocalStorage.read(HookDecision.self, at: HookFiles.file(a.id, "decision.json"))
        precondition(decision.id == a.id && decision.sessionID == "session-a" && decision.toolUseID == "tool-a")
        precondition(decision.answer == exact && store.activeRequest?.status == .sending)
        store.setDraft("Do not change an answer in transit")
        precondition(store.activeRequest?.draft == exact)
        try LocalStorage.write(HookReceipt(id: a.id, submitted: true), to: HookFiles.file(a.id, "receipt.json"))
        store.poll()
        precondition(store.activeRequest?.status == .submitted && store.activeRequest?.submittedAnswer == exact)
        let next = try incoming("session-a", "tool-next")
        try store.ingest(next)
        precondition(store.sessions.count == 2 && store.activeSession?.requests.count == 2)
        precondition(store.activeRequestID == next.id && store.activeRequest?.draft == "")
        store.setComposer("Why did we choose that?")
        store.prepare(.discuss)
        precondition(store.preview?.text.contains("Human's explicitly submitted answer: " + exact) == true,
            "Follow-up discussion must include the actual accepted answer, including the human's final edits")
        precondition(store.activeRequest?.draft.isEmpty == true)
        store.selectRequest(a.id)
        precondition(store.activeRequest?.draft == exact)
        store.selectRequest(next.id)
        store.setDraft("Survive restart")
        store.selectSession("session-b")
        store.cancel()
        let cancelled = try LocalStorage.read(HookDecision.self, at: HookFiles.file(b.id, "decision.json"))
        precondition(cancelled.answer == nil && cancelled.sessionID == "session-b")
        store.stop()
        let restored = SessionStore(connection: connection)
        restored.selectSession("session-a")
        precondition(restored.activeRequest?.draft == "Survive restart")
        precondition(restored.activeRequest?.status == .inactive && !restored.canSubmit)
        restored.selectRequest(a.id)
        precondition(restored.activeRequest?.status == .submitted)
        restored.selectSession("session-b")
        restored.deleteSession("session-b")
        precondition(restored.sessions.count == 1 && restored.sessions[0].id == "session-a")
        let disk = try LocalStorage.read([SavedSession].self, at: root.appendingPathComponent("sessions.json"))
        precondition(disk.count == 1)
        var legacy = disk[0]
        legacy.requests[0].proposal = "A legacy unclassified suggestion?"
        legacy.messages.append(MaieMessage(requestID: legacy.requests[0].id, role: "assistant",
            text: "A legacy unclassified suggestion?", created: Date()))
        let legacyURL = root.appendingPathComponent("legacy.json")
        try LocalStorage.write([legacy], to: legacyURL)
        let migrated = SessionStore(connection: connection, historyURL: legacyURL)
        migrated.selectRequest(legacy.requests[0].id)
        precondition(migrated.activeRequest?.proposal == nil && migrated.activeRequest?.draft == exact)
        precondition(migrated.activeSession?.discussionMessages.contains(where: { $0.text == "A legacy unclassified suggestion?" }) == true)

        // Capture a deletion target, then change selection as an arriving question can do.
        let deletionTarget = "session-a"
        let otherSession = SavedSession(id: "session-c", requests: legacy.requests)
        try LocalStorage.write([legacy, otherSession], to: legacyURL)
        let switchedStore = SessionStore(connection: connection, historyURL: legacyURL)
        switchedStore.selectSession("session-c")
        switchedStore.deleteSession(deletionTarget)
        precondition(switchedStore.sessions.map(\.id) == ["session-c"])
        precondition(switchedStore.activeSessionID == "session-c",
            "Deleting a captured session must preserve a newly selected session")

        // A rejected oversized save must preserve the last readable history on disk.
        let boundedURL = root.appendingPathComponent("bounded-history.json")
        try LocalStorage.write([legacy], to: boundedURL)
        let boundedStore = SessionStore(connection: connection, historyURL: boundedURL)
        boundedStore.selectRequest(legacy.requests.last!.id)
        let previousHistory = try Data(contentsOf: boundedURL)
        boundedStore.setDraft(String(repeating: "x", count: LocalStorage.defaultReadLimit + 1))
        precondition(boundedStore.error.contains("Recent edits are not saved"))
        let preservedHistory = try Data(contentsOf: boundedURL)
        precondition(preservedHistory == previousHistory)
        boundedStore.setDraft("Recovered within the storage limit")
        let recoveredHistory = try LocalStorage.read([SavedSession].self, at: boundedURL)
        precondition(recoveredHistory[0].requests.last?.draft == "Recovered within the storage limit")
        precondition(boundedStore.error.isEmpty, "A successful recovery save clears its own storage warning")

        let transcript = root.appendingPathComponent("session-a.jsonl")
        let lines: [[String: Any]] = [
            ["type": "user", "sessionId": "session-a", "uuid": "u1", "message": ["content": exact]],
            ["type": "assistant", "sessionId": "session-a", "uuid": "a1", "message": ["content": [["type": "text", "text": "Local preferences stay on this Mac."], ["type": "tool_use", "input": ["secret": "TOOL-EXCLUDED"]]]]],
            ["type": "assistant", "sessionId": "session-other", "message": ["content": "OTHER-SESSION-EXCLUDED"]],
            ["type": "api-request-blob", "sessionId": "session-a", "message": ["content": "SNAPSHOT-EXCLUDED"]]
        ]
        var data = Data()
        for line in lines { data.append(try JSONSerialization.data(withJSONObject: line)); data.append(10) }
        try data.write(to: transcript)
        let context = TranscriptContext.capture(path: transcript.path, sessionID: "session-a", question: "Preferences?")
        precondition(context.text.contains(exact.trimmingCharacters(in: .whitespacesAndNewlines)))
        precondition(context.text.contains("Local preferences"))
        precondition(!context.text.contains("EXCLUDED"))
        precondition(TranscriptContext.capture(path: nil, sessionID: "session-a", question: "Lagged question").text.isEmpty)
        // Exercise real send entry points with a synthetic responder: never use credentials or a model.
        let otherTranscript = root.appendingPathComponent("session-a-other.jsonl")
        try data.write(to: otherTranscript)
        func savedQuestion(_ tool: String, path: String?) -> SavedRequest {
            var request = SavedRequest(id: UUID(), toolUseID: tool, cwd: "/tmp/fictional-project",
                transcriptPath: path, question: "Where should preferences live?", options: [],
                created: Date(), expiresAt: Date().addingTimeInterval(-1))
            request.status = .inactive; request.draft = exact
            return request
        }
        let firstSend = savedQuestion("send-first", path: transcript.path)
        let secondSource = savedQuestion("send-second-source", path: otherTranscript.path)
        let otherSend = savedQuestion("send-other-session", path: nil)
        let sendHistoryURL = root.appendingPathComponent("send-flow.json")
        try LocalStorage.write([
            SavedSession(id: "session-a", requests: [firstSend, secondSource]),
            SavedSession(id: "session-other", requests: [otherSend])
        ], to: sendHistoryURL)
        let sendConnection = OpenAIConnection(loadSaved: false)
        sendConnection.billing = "OpenAI API · separate billing"
        sendConnection.models = [ModelChoice(id: "gpt-6.1-sol", name: "GPT-6.1 Sol"),
                                 ModelChoice(id: "gpt-6-luna", name: "GPT-6 Luna")]
        sendConnection.selectedModel = "gpt-6.1-sol"
        var sentPreviews: [ModelPreview] = []
        let sendStore = SessionStore(connection: sendConnection, historyURL: sendHistoryURL, modelResponder: { preview in
            sentPreviews.append(preview)
            return preview.action == .discuss ? "A synthetic explanation." : #"{"kind":"proposal","text":"Synthetic reviewed answer"}"#
        })
        func settleSend() async {
            for _ in 0..<100 where !sendStore.busySessionIDs.isEmpty { await Task.yield() }
            precondition(sendStore.busySessionIDs.isEmpty, "A synthetic response did not settle")
        }
        sendStore.selectSession("session-a"); sendStore.selectRequest(firstSend.id)
        sendStore.setDraft(" ")
        sendStore.requestModel(.suggest)
        precondition(sendStore.preview == nil && sentPreviews.isEmpty,
            "Suggest answer needs a draft or discussion rather than inventing human intent")
        sendStore.setDraft(exact)
        sendStore.setComposer("Explain local preferences simply.")
        sendStore.requestModel(.discuss)
        precondition(sendStore.previewNeedsConfirmation && sentPreviews.isEmpty,
            "The first send in a session must wait for scope confirmation")
        sendStore.preview = nil
        sendStore.requestModel(.discuss)
        precondition(sendStore.previewNeedsConfirmation && sentPreviews.isEmpty,
            "Dismissing a review must not grant permission")
        sendStore.sendPreview(); await settleSend()
        precondition(sentPreviews.count == 1 && sendStore.activeRequest?.draft == exact)
        for action in [ModelAction.discuss, .suggest] {
            let previousCount = sentPreviews.count
            sendStore.setComposer("A harmless follow-up.")
            sendStore.requestModel(action)
            precondition(sendStore.preview == nil)
            await settleSend()
            precondition(sentPreviews.count == previousCount + 1 && sentPreviews.last?.action == action,
                "An explicit action in an approved session must send once without another popup")
            precondition(sendStore.activeRequest?.draft == exact && !sendStore.canSubmit,
                "Model actions must preserve the draft and never reactivate the old Claude request")
        }
        sendStore.setDraft("")
        let beforeDiscussionSuggestion = sentPreviews.count
        sendStore.requestModel(.suggest); await settleSend()
        precondition(sentPreviews.count == beforeDiscussionSuggestion + 1 && sendStore.activeRequest?.draft == "",
            "Suggest answer must work from discussion alone and leave an empty draft unchanged")
        precondition(sendStore.activeRequest?.proposal == "Synthetic reviewed answer")
        sendStore.setDraft(exact)
        sendConnection.selectedModel = "gpt-6-luna"; sendConnection.selectEffort(.none)
        sendStore.setComposer("Explain with the selected model.")
        sendStore.requestModel(.discuss)
        precondition(sendStore.preview == nil); await settleSend()
        precondition(sentPreviews.last?.model == "gpt-6-luna" && sentPreviews.last?.effort == ReasoningEffort.none)
        sendStore.enableContext(true)
        let beforeContext = sentPreviews.count
        sendStore.setComposer("Explain using the selected history.")
        sendStore.requestModel(.discuss)
        precondition(sendStore.previewNeedsConfirmation && sentPreviews.count == beforeContext,
            "Adding a Claude transcript source requires confirmation")
        sendStore.sendPreview(); await settleSend()
        sendStore.enableContext(false); sendStore.setComposer("Explain without extra history."); sendStore.requestModel(.discuss)
        precondition(sendStore.preview == nil); await settleSend()
        sendStore.enableContext(true); sendStore.setComposer("Explain with the approved history."); sendStore.requestModel(.discuss)
        precondition(sendStore.preview == nil,
            "Sending a narrower request must preserve the previously approved history source")
        await settleSend()
        sendStore.selectRequest(secondSource.id); sendStore.requestModel(.suggest)
        precondition(sendStore.previewNeedsConfirmation,
            "A different transcript source in the same session requires confirmation")
        sendStore.preview = nil
        sendStore.selectSession("session-other"); sendStore.setComposer("Explain another session.")
        let beforeOtherSession = sentPreviews.count
        sendStore.requestModel(.discuss)
        precondition(sendStore.previewNeedsConfirmation && sentPreviews.count == beforeOtherSession)
        sendStore.preview = nil
        sendStore.selectSession("session-a"); sendStore.selectRequest(firstSend.id)
        sendStore.setComposer("Review before a connection change.")
        sendStore.prepare(.discuss)
        sendConnection.useChatGPT()
        sendStore.sendPreview()
        precondition(sentPreviews.count == beforeOtherSession && sendStore.preview == nil,
            "A changed connection must invalidate even a manually reviewed request")
        sendConnection.billing = "OpenAI API · separate billing"
        sendConnection.models = [ModelChoice(id: "gpt-6.1-sol", name: "GPT-6.1 Sol")]
        sendConnection.selectedModel = "gpt-6.1-sol"
        sendStore.requestModel(.discuss)
        precondition(sendStore.previewNeedsConfirmation,
            "Returning to the same billing label with a new connection needs fresh confirmation")
        let restoredSendStore = SessionStore(connection: sendConnection, historyURL: sendHistoryURL, modelResponder: { _ in
            preconditionFailure("Restart silently restored send approval")
        })
        restoredSendStore.selectSession("session-a"); restoredSendStore.selectRequest(firstSend.id)
        restoredSendStore.setComposer("Review after restart.")
        restoredSendStore.requestModel(.discuss)
        precondition(restoredSendStore.previewNeedsConfirmation,
            "Restart must not silently restore a prior run's send approval")
        var stream = ResponseStream()
        try stream.consume(#"{"type":"response.output_text.delta","delta":"Hello"}"#)
        do { _ = try stream.result(); preconditionFailure("A partial response must fail") } catch { }
        try stream.consume(#"{"type":"response.completed","response":{"status":"completed"}}"#)
        let completedText = try stream.result()
        precondition(completedText == "Hello")
        try stream.consume(#"{"type":"response.failed"}"#)
        do { _ = try stream.result(); preconditionFailure("A failed stream must fail") } catch { }
        let validClaims: [String: Any] = ["iss": OpenAIWire.issuer, "aud": "test-client", "sub": "test-subject", "nonce": "test-nonce", "exp": Date().timeIntervalSince1970 + 300]
        try OpenAIWire.validateClaims(validClaims, clientID: "test-client", nonce: "test-nonce")
        for (key, value) in [("iss", "https://invalid.example"), ("aud", "other-client"), ("nonce", "wrong-nonce"), ("sub", "")] {
            var invalid = validClaims; invalid[key] = value
            do { try OpenAIWire.validateClaims(invalid, clientID: "test-client", nonce: "test-nonce"); preconditionFailure("Invalid identity claim accepted") } catch { }
        }
        var expired = validClaims; expired["exp"] = Date().timeIntervalSince1970 - 1
        do { try OpenAIWire.validateClaims(expired, clientID: "test-client", nonce: "test-nonce"); preconditionFailure("Expired identity accepted") } catch { }
        let form = String(data: OpenAIWire.form(["test": "a+b&c=d\n"]), encoding: .utf8)!
        precondition(form == "test=a%2Bb%26c%3Dd%0A")
        let sol = ModelChoice(id: "gpt-6.1-sol", name: "GPT-6.1 Sol")
        let requestBody = try OpenAIWire.responseBody(model: sol, effort: .high,
            input: [["role": "user", "content": exact]], instructions: "Synthetic check", structuredDraft: true)
        let serializedBody = try JSONSerialization.data(withJSONObject: requestBody)
        let decodedBody = try JSONSerialization.jsonObject(with: serializedBody) as! [String: Any]
        precondition((decodedBody["reasoning"] as? [String: String])?["effort"] == "high")
        precondition((decodedBody["text"] as? [String: Any])?["format"] is [String: Any],
            "Effort must coexist with structured proposal/clarification responses")
        precondition(decodedBody["store"] as? Bool == false && decodedBody["stream"] as? Bool == true)
        precondition((decodedBody["input"] as? [[String: String]])?.first?["content"] == exact)
        let unknownModel = ModelChoice(id: "gpt-unknown-test", name: "Unknown test model")
        let defaultBody = try OpenAIWire.responseBody(model: unknownModel, effort: .modelDefault,
            input: [], instructions: "Synthetic check", structuredDraft: false)
        precondition(defaultBody["reasoning"] == nil && defaultBody["text"] == nil,
            "Unrecognized models must retain their default without an unsupported effort parameter")
        do {
            _ = try OpenAIWire.responseBody(model: sol, effort: .none, input: [], instructions: "", structuredDraft: false)
            preconditionFailure("Unsupported effort must not reach the network")
        } catch { }
        let suiteName = "local.maie.effort-checks." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let firstSettings = OpenAIConnection(loadSaved: false, preferences: preferences)
        firstSettings.models = [sol, unknownModel]
        firstSettings.selectedModel = sol.id
        precondition(firstSettings.selectedEffort == .medium)
        firstSettings.selectEffort(.high)
        firstSettings.selectedModel = unknownModel.id
        precondition(firstSettings.selectedEffort == .modelDefault)
        firstSettings.selectEffort(.high)
        precondition(firstSettings.selectedEffort == .modelDefault, "Reject unsupported effort selections")
        firstSettings.selectedModel = sol.id
        precondition(firstSettings.selectedEffort == .high, "Restore effort when returning to a model")
        let restoredSettings = OpenAIConnection(loadSaved: false, preferences: preferences)
        restoredSettings.models = [sol]
        restoredSettings.selectedModel = sol.id
        precondition(restoredSettings.selectedEffort == .high, "Keep effort across connection lifetimes")
        precondition(preferences.string(forKey: "maie.selectedModel") == sol.id)
        // Exercise the JWK-to-Security RSA conversion used by real OIDC verification.
        let privateKey = SecKeyCreateRandomKey([kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: false]] as CFDictionary, nil)!
        let publicKey = SecKeyCopyPublicKey(privateKey)!
        let exported = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        var cursor = 0
        func readDER(_ expected: UInt8) -> Data {
            precondition(exported[cursor] == expected); cursor += 1
            var length = Int(exported[cursor]); cursor += 1
            if length & 0x80 != 0 {
                let count = length & 0x7f; length = 0
                for _ in 0..<count { length = (length << 8) | Int(exported[cursor]); cursor += 1 }
            }
            let start = cursor
            if expected != 0x30 { cursor += length }
            return exported.subdata(in: start..<(start + length))
        }
        _ = readDER(0x30)
        let modulus = readDER(0x02), exponent = readDER(0x02)
        let rebuilt = try OpenAIWire.rsaKey(modulus: modulus, exponent: exponent)
        let signedText = Data("Synthetic identity signature".utf8)
        let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, signedText as CFData, nil)!
        precondition(SecKeyVerifySignature(rebuilt, .rsaSignatureMessagePKCS1v15SHA256, signedText as CFData, signature, nil))
        precondition(!SecKeyVerifySignature(rebuilt, .rsaSignatureMessagePKCS1v15SHA256, Data("Tampered identity".utf8) as CFData, signature, nil))
        let cancelledCallback = OAuthCallback()
        cancelledCallback.cancel()
        do { try await cancelledCallback.start(); preconditionFailure("A cancelled callback must not start") }
        catch is CancellationError { }
        var openedAfterCancellation = false
        do {
            _ = try await cancelledCallback.wait { openedAfterCancellation = true }
            preconditionFailure("A cancelled callback must not wait again")
        } catch is CancellationError { }
        precondition(!openedAfterCancellation)

        let waitingCallback = OAuthCallback()
        let waitingTask = Task { try await waitingCallback.wait() }
        await Task.yield()
        waitingTask.cancel()
        do { _ = try await waitingTask.value; preconditionFailure("A cancelled callback wait must settle") }
        catch is CancellationError { }

        let startingCallback = OAuthCallback()
        let startingTask = Task { try await startingCallback.start() }
        await Task.yield()
        startingCallback.cancel(); startingTask.cancel()
        // Readiness may win the race; either outcome must settle, and later wait must stay cancelled.
        do { try await startingTask.value } catch is CancellationError { }
        do { _ = try await startingCallback.wait(); preconditionFailure("Startup cancellation must remain terminal") }
        catch is CancellationError { }
        print("Functional checks passed: isolated sessions/requests, exact Unicode drafts, explicit approval, hook receipt, restart without reactivation, deletion, bounded transcript filtering, completed-stream requirement.")
        print("Review regressions passed: captured deletion target, bounded history with recovery, callback cancellation before readiness/wait.")
    }
}

@MainActor private final class RefreshFixture {
    var credentials: [String: Data] = [:]
    var pending: [CheckedContinuation<Data, Error>] = []
    var refreshCount = 0
    var modelCount = 0
    var services: ConnectionServices {
        ConnectionServices(request: { request in
            switch request.url!.path {
            case "/api/accounts/oauth/token":
                self.refreshCount += 1
                return try await withCheckedThrowingContinuation { self.pending.append($0) }
            case "/api/accounts/oauth/revoke": return Data()
            case "/v1/models":
                self.modelCount += 1
                return Data(#"{"models":[{"visibility":"list","slug":"test-model","display_name":"Test"}]}"#.utf8)
            default: preconditionFailure("Unexpected request in offline refresh check")
            }
        }, readCredential: { self.credentials[$0] }, saveCredential: { self.credentials[$1] = $0 },
           deleteCredential: { self.credentials.removeValue(forKey: $0) })
    }
    func release() {
        pending.removeFirst().resume(returning: Data(#"{"access_token":"synthetic-new","refresh_token":"synthetic-replacement","scope":"resource.invoke chatgpt.tokens.use.direct","token_type":"bearer","expires_in":3600}"#.utf8))
    }
    func waitForRefreshes(_ count: Int) async {
        for _ in 0..<10_000 {
            if refreshCount >= count { return }
            await Task.yield()
        }
        preconditionFailure("Synthetic refresh did not start")
    }
}

extension ModelChecks {
    @MainActor static func checkQuestionSets() throws {
        let previousRoot = ProcessInfo.processInfo.environment["MAIE_DATA_DIR"]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maie-question-set-" + UUID().uuidString)
        setenv("MAIE_DATA_DIR", root.path, 1)
        defer {
            try? FileManager.default.removeItem(at: root)
            if let previousRoot { setenv("MAIE_DATA_DIR", previousRoot, 1) } else { unsetenv("MAIE_DATA_DIR") }
        }
        let connection = OpenAIConnection(loadSaved: false)
        connection.models = [ModelChoice(id: "test-model", name: "Test")]
        connection.selectedModel = "test-model"; connection.billing = "OpenAI API · separate billing"
        let store = SessionStore(connection: connection, modelResponder: { _ in
            preconditionFailure("A question-set preview attempted inference")
        })
        try store.start(); defer { store.stop() }
        let runID = try LocalStorage.read(ServiceLease.self, at: HookFiles.lease).runID
        func payload(_ session: String, _ tool: String, count: Int = 4) -> [String: Any] {
            let questions: [[String: Any]] = (0..<count).map { index in
                ["question": "Synthetic question \(index + 1)?", "multiSelect": index == 1,
                 "options": [["label": "First", "description": "One"], ["label": "Second", "description": "Two"],
                             ["label": "Third", "description": "Three"], ["label": "Fourth", "description": "Four"]]]
            }
            return ["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "session_id": session,
                    "tool_use_id": tool, "cwd": "/tmp/fictional-project", "tool_input": ["questions": questions, "unknown": "preserve"]]
        }
        func incoming(_ session: String, _ tool: String, count: Int = 4) throws -> HookEnvelope {
            let id = UUID()
            try LocalStorage.directory(HookFiles.folder(id))
            try LocalStorage.write(Date(), to: HookFiles.file(id, "heartbeat.json"))
            return HookEnvelope(id: id, runID: runID, pid: getpid(), created: Date(), timeout: 1_800,
                payload: try JSONSerialization.data(withJSONObject: payload(session, tool, count: count)))
        }
        for count in 1...4 {
            var value = payload("optional-flag", "optional-flag", count: count)
            var input = value["tool_input"] as! [String: Any]
            var questions = input["questions"] as! [[String: Any]]
            questions[0].removeValue(forKey: "multiSelect")
            input["questions"] = questions; value["tool_input"] = input
            let request = try QuestionRequest.parse(JSONSerialization.data(withJSONObject: value))!
            precondition(request.questions.count == count && !request.questions[0].multiSelect)
        }
        let batch = try incoming("batch-session", "batch-tool")
        let parsed = try QuestionRequest.parse(batch.payload)!
        precondition(parsed.questions.count == 4 && parsed.questions[1].multiSelect)
        let exact = "  \u{0394}\u{03bf}\u{03ba}\u{03b9}\u{03bc}\u{03ae}\n\"quotes\" $(literal) \u{1fae7}\n"
        // Old history has none of the optional group/selection fields.
        var oldQuestion = SavedRequest(id: UUID(), toolUseID: "old-tool", cwd: "/tmp/fictional-project", transcriptPath: nil,
            question: "Old saved question?", options: [], created: Date(), expiresAt: .distantPast)
        oldQuestion.status = .inactive; oldQuestion.draft = exact; oldQuestion.composer = "Saved old composer"
        let oldHistory = root.appendingPathComponent("old-history.json")
        try LocalStorage.write([SavedSession(id: "old-session", requests: [oldQuestion])], to: oldHistory)
        let oldStore = SessionStore(connection: connection, historyURL: oldHistory)
        precondition(oldStore.activeRequest?.draft == exact && oldStore.activeRequest?.composer == "Saved old composer")
        precondition(oldStore.activeRequest?.groupID == nil && oldStore.activeGroup.count == 1)
        let answers = Dictionary(uniqueKeysWithValues: parsed.questions.enumerated().map { ($0.element.question, $0.offset == 0 ? exact : "Answer \($0.offset)") })
        let output = try parsed.approvedOutput(answers: answers)
        let returned = (output["hookSpecificOutput"] as! [String: Any])["updatedInput"] as! [String: Any]
        precondition(returned["answers"] as! [String: String] == answers && returned["unknown"] as? String == "preserve")
        for invalid in [[:], [parsed.question: exact], answers.merging(["Foreign question": "Wrong"], uniquingKeysWith: { $1 }),
                        answers.merging([parsed.question: " "], uniquingKeysWith: { $1 }),
                        answers.merging([parsed.question: String(repeating: "x", count: 8_193)], uniquingKeysWith: { $1 })] {
            do { _ = try parsed.approvedOutput(answers: invalid); preconditionFailure("Partial or invalid answer set accepted") } catch { }
        }
        do { _ = try parsed.approvedOutput(answer: "Partial"); preconditionFailure("Legacy partial answer accepted for batch") } catch { }
        for mode in 0..<4 {
            var value = payload("invalid", "invalid")
            var input = value["tool_input"] as! [String: Any]
            var questions = input["questions"] as! [[String: Any]]
            if mode == 0 { questions[1]["question"] = questions[0]["question"] }
            if mode == 1 { questions[0]["multiSelect"] = 0 }
            if mode == 2 { questions.append(questions[0]) }
            if mode == 3 { questions[0]["options"] = [["label": "First", "description": "One"], ["label": "First", "description": "Duplicate"]] }
            input["questions"] = questions; value["tool_input"] = input
            do { _ = try QuestionRequest.parse(JSONSerialization.data(withJSONObject: value)); preconditionFailure("Invalid question set accepted") } catch { }
        }
        try store.ingest(batch)
        precondition(store.activeGroup.count == 4 && store.activeRequestID == batch.id && store.questionNotice?.count == 4)
        let ids = store.activeGroup.map(\.id)
        store.setDraft(exact); store.setComposer("Explain this question")
        store.applyDraftResponse(try DraftResponse.parse(#"{"kind":"clarification","text":"First question discussion only"}"#), sessionID: "batch-session", requestID: ids[0])
        store.prepare(.discuss)
        precondition(store.preview != nil)
        store.moveQuestion(1)
        precondition(store.preview == nil && store.activeRequest?.draft == "" && store.activeRequest?.composer == "")
        precondition(store.discussionMessages(for: store.activeRequest!).isEmpty)
        store.requestModel(.suggest)
        precondition(store.preview == nil, "Another page's discussion cannot authorize a suggestion on this empty page")
        let choices = store.activeRequest!.options
        store.choose(choices[0]); store.choose(choices[2])
        precondition(store.activeRequest?.draft == "First, Third")
        store.choose(choices[0]); precondition(store.activeRequest?.draft == "Third")
        store.setDraft("Third, plus a custom Other answer")
        precondition(store.activeRequest?.selectedOptions == nil)
        store.setComposer("Discuss the second page")
        store.prepare(.discuss)
        precondition(store.preview?.text.contains("First question discussion only") == false)
        store.moveQuestion(1); store.setDraft("Third answer")
        store.moveQuestion(1); store.setDraft("Fourth answer")
        precondition(store.allAnswersReady && !store.canSubmit)
        store.submit()
        precondition(!FileManager.default.fileExists(atPath: HookFiles.file(batch.id, "decision.json").path), "Next/navigation must never send partial answers")
        store.beginAnswerReview(); precondition(store.canSubmit)
        store.selectRequest(ids[0]); precondition(!store.canSubmit && store.activeRequest?.draft == exact)
        precondition(store.activeRequest?.composer == "Explain this question")
        store.setDraft(String(repeating: "x", count: 8_193)); precondition(!store.canReviewAnswers)
        store.setDraft(exact); store.beginAnswerReview(); store.submit()
        let decision = try LocalStorage.read(HookDecision.self, at: HookFiles.file(batch.id, "decision.json"), limit: HookDecision.maxBytes)
        precondition(decision.id == batch.id && decision.answer == nil && decision.answers?.count == 4)
        precondition(decision.answers?[parsed.question] == exact)
        precondition(store.activeGroup.allSatisfy { $0.status == .sending && $0.submittedAnswer == $0.draft })
        store.setDraft("Cannot replace an answer in transit"); precondition(store.activeRequest?.draft == exact)
        try LocalStorage.write(HookReceipt(id: batch.id, submitted: true), to: HookFiles.file(batch.id, "receipt.json"))
        store.poll(); precondition(store.activeGroup.allSatisfy { $0.status == .submitted })
        // A new set must notify without replacing an editor, even after an earlier submission.
        store.editorFocused = true
        let next = try incoming("batch-session", "next-batch")
        try store.ingest(next)
        precondition(store.activeRequestID == ids[0] && store.questionNotice?.id == next.id)
        precondition(store.pendingQuestions.count == 1 && store.pendingQuestions[0].count == 4)
        let target = store.pendingQuestions[0]
        let other = try incoming("other-session", "other-batch")
        try store.ingest(other)
        precondition(store.activeRequestID == ids[0] && store.activeRequest?.draft == exact)
        precondition(store.pendingQuestions.count == 2, "Count request sets, not their pages")
        let staleTarget = store.pendingQuestions.first { $0.id == other.id }!
        store.dismissQuestionNotice()
        precondition(store.pendingQuestions.count == 2, "Dismissal must not hide pending requests")
        let foreignTarget = QuestionNotice(id: target.id, sessionID: "other-session", title: "Synthetic", count: 4)
        precondition(!store.showPendingQuestion(foreignTarget) && store.activeRequestID == ids[0])
        try FileManager.default.removeItem(at: HookFiles.file(other.id, "heartbeat.json"))
        precondition(!store.showPendingQuestion(staleTarget) && store.activeRequestID == ids[0], "Stale menu targets cannot navigate")
        store.poll()
        precondition(store.pendingQuestions.count == 1)
        precondition(store.showPendingQuestion(target))
        precondition(store.activeRequestID == next.id && store.activeGroup.count == 4 && store.questionNotice == nil)
        store.setDraft("Saved across restart"); store.moveQuestion(1); store.setDraft("Another saved page")
        let cancelledID = store.activeRequest!.bridgeID
        store.cancel()
        let cancelled = try LocalStorage.read(HookDecision.self, at: HookFiles.file(cancelledID, "decision.json"))
        precondition(cancelled.answer == nil && cancelled.answers == nil && store.activeGroup.allSatisfy { $0.status == .cancelled })
        precondition(store.pendingQuestions.isEmpty && !store.showPendingQuestion(target))
        store.editorFocused = false
        let restoredBatch = try incoming("batch-session", "restored-batch")
        try store.ingest(restoredBatch)
        store.setDraft(exact); store.moveQuestion(1); store.setDraft("Second restored draft")
        store.stop()
        precondition(store.questionNotice == nil, "Stopped/expired sets must not retain a new-question notice")
        let restored = SessionStore(connection: connection)
        restored.selectSession("batch-session")
        precondition(restored.activeGroup.count == 4 && restored.activeGroup.allSatisfy { $0.status == .inactive })
        precondition(restored.activeGroup[0].draft == exact && restored.activeGroup[1].draft == "Second restored draft")
        precondition(!restored.canSubmit && restored.pendingQuestions.isEmpty)
        print("Question-set checks passed: four questions, exact complete answers, multi-select/custom text, per-page drafts/discussion, review gate, notices, cancellation and inactive restoration.")
    }

    @MainActor static func checkQuestionTaskRouting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maie-page-task-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try LocalStorage.directory(root)
        let connection = OpenAIConnection(loadSaved: false)
        connection.billing = "OpenAI API · separate billing"
        connection.models = [ModelChoice(id: "test-model", name: "Test")]; connection.selectedModel = "test-model"
        let firstID = UUID(), secondID = UUID()
        var first = SavedRequest(id: firstID, toolUseID: "batch", cwd: "/tmp/fictional-project", transcriptPath: nil,
            question: "First page?", options: [], created: Date(), expiresAt: .distantPast)
        first.groupID = firstID; first.questionIndex = 0; first.questionCount = 2; first.status = .inactive; first.draft = "First intent"
        var second = SavedRequest(id: secondID, toolUseID: "batch", cwd: "/tmp/fictional-project", transcriptPath: nil,
            question: "Second page?", options: [], created: Date(), expiresAt: .distantPast)
        second.groupID = firstID; second.questionIndex = 1; second.questionCount = 2; second.status = .inactive; second.draft = "Second intent"
        let history = root.appendingPathComponent("history.json")
        try LocalStorage.write([SavedSession(id: "batch", requests: [first, second])], to: history)
        var continuation: CheckedContinuation<String, Never>?
        let store = SessionStore(connection: connection, historyURL: history, modelResponder: { _ in
            await withCheckedContinuation { continuation = $0 }
        })
        store.requestModel(.suggest); store.sendPreview()
        for _ in 0..<10_000 where continuation == nil { await Task.yield() }
        precondition(continuation != nil && store.isThinking(firstID))
        store.moveQuestion(1)
        precondition(store.activeRequestID == secondID && !store.isThinking(secondID))
        continuation!.resume(returning: #"{"kind":"proposal","text":"Proposal for the first page"}"#)
        for _ in 0..<10_000 where !store.busySessionIDs.isEmpty { await Task.yield() }
        precondition(store.activeRequest?.proposal == nil && store.activeRequest?.draft == "Second intent")
        store.moveQuestion(-1)
        precondition(store.activeRequest?.proposal == "Proposal for the first page" && store.activeRequest?.draft == "First intent")
        store.acceptProposal()
        precondition(store.activeRequest?.draft == "Proposal for the first page")
        store.moveQuestion(1); precondition(store.activeRequest?.draft == "Second intent")
        print("Question task routing passed: a late proposal stays with its original page until explicitly accepted.")
    }

    @MainActor static func checkRefreshLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maie-refresh-checks-" + UUID().uuidString)
        let previousRoot = ProcessInfo.processInfo.environment["MAIE_DATA_DIR"]
        setenv("MAIE_DATA_DIR", root.path, 1)
        let suite = "local.maie.refresh-checks." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            if let previousRoot { setenv("MAIE_DATA_DIR", previousRoot, 1) } else { unsetenv("MAIE_DATA_DIR") }
        }
        try LocalStorage.directory(root)
        let fixture = RefreshFixture()
        let account = ChatGPTAccount(clientID: "synthetic-client", subject: "synthetic-subject", email: "synthetic@example.invalid",
            accessToken: "synthetic-old", refreshToken: "synthetic-refresh", idToken: "", expiresAt: .distantPast, scopes: [])
        func connected() throws -> OpenAIConnection {
            fixture.credentials[account.clientID] = try JSONEncoder().encode(account)
            preferences.set(account.clientID, forKey: "maie.activeAccount")
            let connection = OpenAIConnection(preferences: preferences, services: fixture.services)
            connection.models = [ModelChoice(id: "test-model", name: "Test")]
            connection.selectedModel = "test-model"
            return connection
        }
        let connection = try connected()
        var question = SavedRequest(id: UUID(), toolUseID: "synthetic-tool", cwd: "/tmp/fictional-project", transcriptPath: nil,
            question: "A synthetic question", options: [], created: Date(), expiresAt: .distantPast)
        question.status = .inactive; question.composer = "A synthetic message"
        let history = root.appendingPathComponent("history.json")
        try LocalStorage.write([SavedSession(id: "synthetic-session", requests: [question])], to: history)
        var settled = false
        let store = SessionStore(connection: connection, historyURL: history, modelResponder: { _ in
            defer { settled = true }
            try await connection.loadModels()
            return "Synthetic response"
        })
        store.requestModel(.discuss); store.sendPreview()
        await fixture.waitForRefreshes(1)
        store.deleteSession("synthetic-session")
        precondition(store.busySessionIDs.isEmpty && !connection.busy)
        await connection.signOut()
        let signedOutRevision = connection.authorizationRevision
        fixture.release()
        for _ in 0..<10_000 where !settled { await Task.yield() }
        precondition(settled && !connection.isConnected && fixture.credentials[account.clientID] == nil,
            "A late refresh must not resurrect a signed-out account or its credentials")
        precondition(connection.authorizationRevision == signedOutRevision && fixture.modelCount == 0)
        precondition(preferences.string(forKey: "maie.activeAccount") == nil)

        let other = try connected()
        let old = Task { try await other.loadModels() }
        await fixture.waitForRefreshes(2)
        other.useChatGPT()
        let newer = Task { try await other.loadModels() }
        await fixture.waitForRefreshes(3)
        fixture.release()
        do { try await old.value; preconditionFailure("Stale refresh installed") } catch is CancellationError { }
        let shared = Task { try await other.loadModels() }
        for _ in 0..<100 { await Task.yield() }
        precondition(fixture.refreshCount == 3, "Old cleanup must not remove the newer shared refresh")
        fixture.release()
        try await newer.value; try await shared.value
        let saved = try JSONDecoder().decode(ChatGPTAccount.self, from: fixture.credentials[account.clientID]!)
        precondition(saved.refreshToken == "synthetic-replacement" && other.isConnected)
        precondition(fixture.modelCount == 2)
        print("Refresh lifecycle checks passed: deletion/sign-out rejects late credentials; newer shared refresh survives stale cleanup. No real credentials or network used.")
    }
}

extension ModelChecks {
    @MainActor static func checkReplacementTask() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maie-replacement-checks-" + UUID().uuidString)
        let previousRoot = ProcessInfo.processInfo.environment["MAIE_DATA_DIR"]
        setenv("MAIE_DATA_DIR", root.path, 1)
        defer {
            try? FileManager.default.removeItem(at: root)
            if let previousRoot { setenv("MAIE_DATA_DIR", previousRoot, 1) } else { unsetenv("MAIE_DATA_DIR") }
        }
        let connection = OpenAIConnection(loadSaved: false)
        connection.billing = "OpenAI API · separate billing"
        connection.models = [ModelChoice(id: "test-model", name: "Test")]; connection.selectedModel = "test-model"
        var pending: [CheckedContinuation<String, Never>] = []
        let store = SessionStore(connection: connection, modelResponder: { _ in
            await withCheckedContinuation { pending.append($0) }
        })
        try store.start(); defer { store.stop() }
        let lease = try LocalStorage.read(ServiceLease.self, at: HookFiles.lease)
        func incoming(_ tool: String) throws {
            let id = UUID()
            try LocalStorage.directory(HookFiles.folder(id))
            try LocalStorage.write(Date(), to: HookFiles.file(id, "heartbeat.json"))
            let payload: [String: Any] = ["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion",
                "session_id": "replacement-session", "tool_use_id": tool, "cwd": "/tmp/fictional-project",
                "tool_input": ["questions": [["question": "Synthetic question", "multiSelect": false,
                    "options": [["label": "First", "description": "One"], ["label": "Second", "description": "Two"]]]]]]
            try store.ingest(HookEnvelope(id: id, runID: lease.runID, pid: getpid(), created: Date(), timeout: 30,
                payload: try JSONSerialization.data(withJSONObject: payload)))
            store.setComposer("Synthetic discussion"); store.requestModel(.discuss); store.sendPreview()
        }
        try incoming("old-tool")
        for _ in 0..<10_000 where pending.isEmpty { await Task.yield() }
        precondition(pending.count == 1)
        store.deleteSession("replacement-session")
        try incoming("new-tool")
        for _ in 0..<10_000 where pending.count < 2 { await Task.yield() }
        precondition(pending.count == 2)
        pending.removeFirst().resume(returning: "Cancelled old response")
        for _ in 0..<100 { await Task.yield() }
        precondition(store.busySessionIDs.contains("replacement-session"),
            "Old cancellation cleanup must not clear a replacement request's busy state")
        store.stopResponse()
        pending.removeFirst().resume(returning: "Cancelled new response")
        for _ in 0..<10_000 where !store.busySessionIDs.isEmpty { await Task.yield() }
        precondition(store.busySessionIDs.isEmpty)
        precondition(store.activeSession?.messages.count == 1 && store.activeSession?.messages.first?.role == "user",
            "Stop must still reach the replacement task; neither cancelled response may be installed")
        print("Replacement task check passed: old cancellation preserves the new task and Stop still works.")
    }
}
