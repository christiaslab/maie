import Foundation
import CoreFoundation

enum ProbeError: Error { case invalidRequest, unsupportedQuestion, invalidAnswer }

struct QuestionRequest {
    let sessionID: String
    let toolUseID: String
    let cwd: String
    let input: [String: Any]
    let question: String
    let options: [String]

    static func parse(_ data: Data) throws -> QuestionRequest? {
        guard data.count <= 65_536,
              let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventName = event["hook_event_name"] as? String,
              let toolName = event["tool_name"] as? String else { throw ProbeError.invalidRequest }
        guard eventName == "PreToolUse", toolName == "AskUserQuestion" else { return nil }
        guard let session = event["session_id"] as? String, !session.isEmpty,
              let toolID = event["tool_use_id"] as? String, !toolID.isEmpty,
              let cwd = event["cwd"] as? String, cwd.hasPrefix("/"),
              let input = event["tool_input"] as? [String: Any],
              let questions = input["questions"] as? [[String: Any]] else { throw ProbeError.invalidRequest }
        // This disposable probe deliberately supports one single-choice question only.
        guard questions.count == 1, input["answers"] == nil, input["response"] == nil,
              let question = questions[0]["question"] as? String,
              !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.count <= 4_000,
              let multiSelect = questions[0]["multiSelect"] as? NSNumber,
              CFGetTypeID(multiSelect) == CFBooleanGetTypeID(), !multiSelect.boolValue,
              let options = questions[0]["options"] as? [[String: Any]],
              (2...4).contains(options.count) else { throw ProbeError.unsupportedQuestion }
        let labels = try options.map { option -> String in
            guard let label = option["label"] as? String, !label.isEmpty,
                  let description = option["description"] as? String else { throw ProbeError.invalidRequest }
            return "• \(label) — \(description)"
        }
        return QuestionRequest(sessionID: session, toolUseID: toolID, cwd: cwd,
                               input: input, question: question, options: labels)
    }

    func approvedOutput(answer: String) throws -> [String: Any] {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              answer.utf8.count <= 8_192 else { throw ProbeError.invalidAnswer }
        var updated = input
        updated["answers"] = [question: answer]
        return ["hookSpecificOutput": [
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "The user explicitly submitted this answer in the Maie probe.",
            "updatedInput": updated
        ]]
    }
}

// A continuous clock keeps the deadline valid across Mac sleep/wake.
// Check again on submission, since the timer may not have fired yet after wake.
struct RequestLifetime {
    let parentID: Int32
    let deadline: ContinuousClock.Instant

    init(parentID: Int32, timeout: TimeInterval, now: ContinuousClock.Instant = .now) {
        self.parentID = parentID
        self.deadline = now.advanced(by: .seconds(timeout))
    }

    func isActive(parentID: Int32, now: ContinuousClock.Instant = .now) -> Bool {
        self.parentID > 1 && self.parentID == parentID && now < deadline
    }
}

func stoppedOutput(_ reason: String) -> [String: Any] {
    ["continue": false, "stopReason": reason, "hookSpecificOutput": [
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": reason
    ]]
}

func encodeOutput(_ value: [String: Any]) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    data.append(0x0A)
    return data
}
