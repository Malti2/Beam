import Foundation
import AppKit

struct CommandSpec: Codable, Equatable {
    var kind: String
    var code: String
    var note: String
    var dangerous: Bool

    var isAppleScript: Bool { kind.lowercased().contains("apple") }

    enum CodingKeys: String, CodingKey {
        case kind, code, note, dangerous
    }

    init(kind: String, code: String, note: String, dangerous: Bool) {
        self.kind = kind
        self.code = code
        self.note = note
        self.dangerous = dangerous
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try container.decodeIfPresent(String.self, forKey: .kind)) ?? "shell"
        code = (try container.decodeIfPresent(String.self, forKey: .code)) ?? ""
        note = (try container.decodeIfPresent(String.self, forKey: .note)) ?? ""
        dangerous = (try container.decodeIfPresent(Bool.self, forKey: .dangerous)) ?? false
    }
}

struct ExecResult {
    let command: CommandSpec
    let output: String
    let failed: Bool
}

enum Executor {
    static func run(_ command: CommandSpec) async -> ExecResult {
        await Task.detached(priority: .userInitiated) {
            if command.isAppleScript {
                return runAppleScript(command)
            }
            return runShell(command)
        }.value
    }

    private static func runAppleScript(_ command: CommandSpec) -> ExecResult {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: command.code) else {
            return ExecResult(command: command, output: "Could not compile the AppleScript.", failed: true)
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            return ExecResult(command: command, output: message, failed: true)
        }
        return ExecResult(command: command, output: result.stringValue ?? "OK", failed: false)
    }

    private static func runShell(_ command: CommandSpec) -> ExecResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command.code]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ExecResult(command: command, output: error.localizedDescription, failed: true)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ExecResult(command: command, output: text.isEmpty ? "OK" : text, failed: process.terminationStatus != 0)
    }

    // Client-side safety net on top of the model's own "dangerous" flag.
    private static let dangerousPatterns: [String] = [
        #"\bsudo\b"#,
        #"\brm\s+"#,
        #"\bmkfs"#,
        #"\bdd\s+"#,
        #"\bshutdown\b"#,
        #"\breboot\b"#,
        #"\bhalt\b"#,
        #"\bkill(all)?\s"#,
        #"\bpkill\b"#,
        #"\bdiskutil\s+(erase|partition|apfs\s+delete)"#,
        #"\bchmod\s+-R\s+/"#,
        #"\bchown\s+-R\s+/"#,
        #"\bdefaults\s+delete\b"#,
        #"\blaunchctl\s+(unload|remove)"#,
        #"\bcsrutil\b"#,
        #"\bnvram\b"#,
        #"\|\s*(sudo\s+)?(ba|z)?sh\b"#,
        #"administrator privileges"#
    ]

    static func isDangerous(_ command: CommandSpec) -> Bool {
        if command.dangerous { return true }
        for pattern in dangerousPatterns {
            if command.code.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}
