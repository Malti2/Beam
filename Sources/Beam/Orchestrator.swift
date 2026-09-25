import Foundation
import SwiftUI

struct Step: Identifiable {
    let id = UUID()
    var kind: String
    var title: String
    var code: String
    var isInspect: Bool
    var output: String = ""
    var status: Status = .running

    enum Status {
        case running, ok, failed
    }
}

// Turns a natural-language task into commands by chatting with the
// configured endpoint, then runs them through the Executor.
final class Orchestrator: ObservableObject {
    @Published var input: String = ""
    @Published var isBusy = false
    @Published var steps: [Step] = []
    @Published var pending: [CommandSpec]? = nil
    @Published var answer: String? = nil
    @Published var errorText: String? = nil

    let endpoints: EndpointStore
    private let client = OpenAIClient()

    init(endpoints: EndpointStore) {
        self.endpoints = endpoints
    }

    private var multiPass: Bool {
        UserDefaults.standard.object(forKey: "beam.multiPass") as? Bool ?? true
    }

    private var multiCommand: Bool {
        UserDefaults.standard.object(forKey: "beam.multiCommand") as? Bool ?? true
    }

    private var maxPasses: Int {
        let stored = UserDefaults.standard.integer(forKey: "beam.maxPasses")
        return max(1, stored == 0 ? 3 : stored)
    }

    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        Task { await run(task: text) }
    }

    func confirmPending() {
        guard let commands = pending else { return }
        pending = nil
        Task { await execute(commands) }
    }

    func cancelPending() {
        pending = nil
        answer = "Cancelled."
        isBusy = false
    }

    private func run(task: String) async {
        guard let endpoint = endpoints.selected, !endpoint.model.isEmpty else {
            errorText = "No model configured. Open Settings → Endpoint."
            return
        }
        isBusy = true
        steps = []
        answer = nil
        errorText = nil

        var messages = [
            ChatMessage(role: "system", content: systemPrompt()),
            ChatMessage(role: "user", content: task)
        ]

        let passes = multiPass ? maxPasses : 1
        do {
            for _ in 0..<passes {
                let raw = try await client.chat(
                    baseURL: endpoint.normalizedBase,
                    apiKey: endpoints.apiKey(for: endpoint),
                    model: endpoint.model,
                    messages: messages
                )
                guard let response = parseResponse(raw) else {
                    // Model answered in plain text instead of JSON — show it as-is.
                    answer = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    isBusy = false
                    return
                }
                switch response.action {
                case "message":
                    answer = response.resolvedText ?? "…"
                    isBusy = false
                    return
                case "inspect":
                    guard let command = response.command ?? response.commands?.first else {
                        answer = response.resolvedText
                        isBusy = false
                        return
                    }
                    let result = await appendAndRun(command, inspect: true)
                    messages.append(ChatMessage(role: "assistant", content: raw))
                    messages.append(ChatMessage(
                        role: "user",
                        content: "Output of your inspect command (exit \(result.failed ? "nonzero" : "0")):\n\(result.output)"
                    ))
                    continue
                case "run":
                    var commands = response.commands ?? (response.command.map { [$0] } ?? [])
                    if !multiCommand, commands.count > 1 {
                        commands = Array(commands.prefix(1))
                    }
                    commands = commands.filter { !$0.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    if commands.isEmpty {
                        answer = response.resolvedText ?? "The model returned no command."
                        isBusy = false
                        return
                    }
                    if commands.contains(where: { Executor.isDangerous($0) }) {
                        // Wait for explicit user confirmation; isBusy stays true.
                        pending = commands
                        return
                    }
                    await execute(commands)
                    return
                default:
                    answer = response.resolvedText ?? raw
                    isBusy = false
                    return
                }
            }
            answer = "Too many research passes without a result — please rephrase more precisely."
            isBusy = false
        } catch {
            errorText = error.localizedDescription
            isBusy = false
        }
    }

    private func execute(_ commands: [CommandSpec]) async {
        isBusy = true
        var anyFailed = false
        for command in commands {
            let result = await appendAndRun(command, inspect: false)
            if result.failed {
                anyFailed = true
                break
            }
        }
        answer = anyFailed ? "Stopped — a command failed. See the log above." : "Done."
        isBusy = false
    }

    @discardableResult
    private func appendAndRun(_ command: CommandSpec, inspect: Bool) async -> ExecResult {
        let step = Step(
            kind: command.kind,
            title: command.note.isEmpty ? (inspect ? "Gathering information" : "Command") : command.note,
            code: command.code,
            isInspect: inspect
        )
        withAnimation(.spring(response: 0.3)) {
            steps.append(step)
        }
        let index = steps.count - 1
        let result = await Executor.run(command)
        var finished = steps[index]
        finished.output = result.output
        finished.status = result.failed ? .failed : .ok
        steps[index] = finished
        return result
    }

    struct AIResponse: Decodable {
        var action: String
        var text: String? = nil
        var message: String? = nil
        var commands: [CommandSpec]? = nil
        var command: CommandSpec? = nil

        var resolvedText: String? { text ?? message }
    }

    private func parseResponse(_ raw: String) -> AIResponse? {
        guard let json = extractJSONObject(raw), let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIResponse.self, from: data)
    }

    // Finds the first balanced {...} block, respecting strings and escapes.
    private func extractJSONObject(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else {
                if character == "\"" { inString = true }
                else if character == "{" { depth += 1 }
                else if character == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func systemPrompt() -> String {
        let home = NSHomeDirectory()
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let now = Date().formatted(date: .long, time: .shortened)
        let passesRule = multiPass
            ? "You may use \"inspect\" up to \(maxPasses - 1) times before your final \"run\" answer."
            : "Do NOT use \"inspect\"; answer directly with \"run\" or \"message\"."
        let commandsRule = multiCommand
            ? "You may include multiple commands; they run in order."
            : "Include EXACTLY ONE command."
        return """
        You are Beam, an automation engine inside a native macOS app. The user describes a task in natural language (usually German). You turn it into macOS commands. Today: \(now). System: \(version), shell is zsh, home directory: \(home).

        Respond with exactly ONE JSON object, no markdown fences, no prose around it:
        {"action":"run","commands":[{"kind":"applescript"|"shell","code":"...","note":"short label in the user's language","dangerous":false}]}
        {"action":"inspect","command":{"kind":"shell","code":"...","note":"...","dangerous":false},"text":"short note"}  — read-only information gathering only; the app runs it and shows you the output so you can continue
        {"action":"message","text":"..."}  — clarifying question or information for the user, in the user's language

        Rules:
        - Use "applescript" to control apps, Finder, System Settings and the UI; use "shell" for files, text and terminal work. Pick whichever is the better tool; never wrap osascript inside a shell command.
        - \(passesRule)
        - \(commandsRule)
        - Mark dangerous=true for anything that deletes, overwrites or moves files, kills processes, changes system-wide settings, sends messages or emails, installs software, or touches other apps' data destructively. When in doubt, mark it dangerous.
        - Never use sudo (no password available). Shell commands run from the user's home directory.
        - AppleScript must be complete and compilable as-is. Prefer real application terminology over UI scripting; use "System Events" keystrokes only as a last resort.
        - Keep "note" values short and concrete (e.g. "List Downloads by size").
        """
    }
}
