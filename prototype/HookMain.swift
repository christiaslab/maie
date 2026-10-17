import Foundation

@main struct HookMain {
    static func run() -> (output: [String: Any], receipt: URL?, id: UUID?) {
        do {
            var timeout: TimeInterval = 1_800
            if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--timeout-seconds",
               let value = Double(CommandLine.arguments[2]), value > 0, value <= 1_800 { timeout = value }
            else if CommandLine.arguments.count != 1 { throw ProbeError.invalidRequest }
            let payload = FileHandle.standardInput.readData(ofLength: 65_537)
            return try HookBridgeClient.wait(payload: payload, timeout: timeout)
        } catch {
            return (stoppedOutput("Maie: unsupported or invalid request; no answer sent. One single-choice question is supported."), nil, nil)
        }
    }
    static func main() {
        let result = run()
        do {
            // Exactly one output attempt. An output failure must never append another decision.
            try FileHandle.standardOutput.write(contentsOf: encodeOutput(result.output))
        } catch { exit(2) }
        if let url = result.receipt, let id = result.id {
            let approved = (result.output["hookSpecificOutput"] as? [String: Any])?["permissionDecision"] as? String == "allow"
            try? LocalStorage.write(HookReceipt(id: id, submitted: approved), to: url)
        }
    }
}
