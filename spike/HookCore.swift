import Foundation
import CoreFoundation

enum ProbeError: Error { case invalidRequest, unsupportedQuestion, invalidAnswer }

struct QuestionItem {
    let question: String
    let options: [String]
    let multiSelect: Bool
}

struct QuestionRequest {
    let sessionID: String
    let toolUseID: String
    let cwd: String
    let input: [String: Any]
    let questions: [QuestionItem]
    var question: String { questions[0].question }
    var options: [String] { questions[0].options }

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
              let rawQuestions = input["questions"] as? [[String: Any]],
              (1...4).contains(rawQuestions.count), input["answers"] == nil,
              input["response"] == nil else { throw ProbeError.invalidRequest }
        let questions = try rawQuestions.map { raw -> QuestionItem in
            guard let question = raw["question"] as? String,
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  question.count <= 4_000,
                  let options = raw["options"] as? [[String: Any]],
                  (2...4).contains(options.count) else { throw ProbeError.unsupportedQuestion }
            let multiSelect: Bool
            if let value = raw["multiSelect"] {
                guard let boolean = value as? NSNumber, CFGetTypeID(boolean) == CFBooleanGetTypeID() else {
                    throw ProbeError.invalidRequest
                }
                multiSelect = boolean.boolValue
            } else { multiSelect = false }
            var labels = Set<String>()
            let descriptions = try options.map { option -> String in
                guard let label = option["label"] as? String,
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      labels.insert(label).inserted,
                      let description = option["description"] as? String else { throw ProbeError.invalidRequest }
                return "• \(label): \(description)"
            }
            return QuestionItem(question: question, options: descriptions, multiSelect: multiSelect)
        }
        // Claude keys answers by exact question text, so duplicate keys cannot be represented safely.
        guard Set(questions.map(\.question)).count == questions.count else { throw ProbeError.invalidRequest }
        return QuestionRequest(sessionID: session, toolUseID: toolID, cwd: cwd,
                               input: input, questions: questions)
    }

    func approvedOutput(answer: String) throws -> [String: Any] {
        guard questions.count == 1 else { throw ProbeError.invalidAnswer }
        return try approvedOutput(answers: [question: answer])
    }
    func approvedOutput(answers: [String: String]) throws -> [String: Any] {
        guard Set(answers.keys) == Set(questions.map(\.question)), answers.values.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 8_192
        }) else { throw ProbeError.invalidAnswer }
        var updated = input
        updated["answers"] = answers
        return ["hookSpecificOutput": [
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "The user explicitly submitted these answers in Maie.",
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
