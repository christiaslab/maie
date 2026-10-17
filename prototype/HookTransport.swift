import Foundation
import Darwin

struct ServiceLease: Codable {
    let runID: UUID
    let pid: Int32
    let touched: Date
    var recent: Bool { abs(touched.timeIntervalSinceNow) < 3 && pid > 1 && kill(pid, 0) == 0 }
}

struct HookEnvelope: Codable {
    let id: UUID
    let runID: UUID
    let pid: Int32
    let created: Date
    let timeout: TimeInterval
    let payload: Data
}

struct HookDecision: Codable {
    let id: UUID
    let sessionID: String
    let toolUseID: String
    let answer: String?
}

struct HookReceipt: Codable {
    let id: UUID
    let submitted: Bool
}

enum HookFiles {
    static var root: URL { LocalStorage.root.appendingPathComponent("bridge", isDirectory: true) }
    static var lease: URL { root.appendingPathComponent("service.json") }
    static func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    static func file(_ id: UUID, _ name: String) -> URL { folder(id).appendingPathComponent(name) }
}

// Each helper remains the only process allowed to return its originating hook's output.
// Disk transport does not transfer the authority to approve an expired request.
enum HookBridgeClient {
    static func wait(payload: Data, timeout: TimeInterval) throws -> (output: [String: Any], receipt: URL?, id: UUID?) {
        guard let request = try QuestionRequest.parse(payload) else { return ([:], nil, nil) }
        let lifetime = RequestLifetime(parentID: getppid(), timeout: timeout)
        guard let lease = try? LocalStorage.read(ServiceLease.self, at: HookFiles.lease), lease.recent else {
            return (stoppedOutput("Maie is not running. Open Maie and ask Claude to issue a new question. No answer sent."), nil, nil)
        }
        let id = UUID()
        try LocalStorage.directory(HookFiles.folder(id))
        let receiptURL = HookFiles.file(id, "receipt.json")
        let envelope = HookEnvelope(id: id, runID: lease.runID, pid: getpid(), created: Date(), timeout: timeout, payload: payload)
        try LocalStorage.write(envelope, to: HookFiles.file(id, "request.json"))
        while lifetime.isActive(parentID: getppid()) {
            guard let liveService = try? LocalStorage.read(ServiceLease.self, at: HookFiles.lease),
                  liveService.runID == lease.runID, liveService.recent else { break }
            try LocalStorage.write(Date(), to: HookFiles.file(id, "heartbeat.json"))
            if let response = try? LocalStorage.read(HookDecision.self, at: HookFiles.file(id, "decision.json"), limit: 32_768) {
                guard response.id == id, response.sessionID == request.sessionID, response.toolUseID == request.toolUseID,
                      lifetime.isActive(parentID: getppid()), let answer = response.answer else { break }
                return (try request.approvedOutput(answer: answer), receiptURL, id)
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return (stoppedOutput("Maie: request cancelled, disconnected, or expired; no answer sent. Ask for a new question when ready."), receiptURL, id)
    }
}
