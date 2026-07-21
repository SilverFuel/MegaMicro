import Foundation

/// Provider-neutral hook bridge. It reads one provider hook payload from
/// stdin, forwards only structural metadata to MegaMicro's loopback webhook,
/// and prints the provider's neutral/fail-open response to stdout.
struct BridgeArguments {
    var provider = "generic"
    var event = ""
    var port = 48_802
    var dryRunReport = false

    init(_ values: [String]) {
        var index = 1
        while index < values.count {
            let value = values[index]
            if value == "--provider", index + 1 < values.count { provider = values[index + 1]; index += 2 }
            else if value == "--event", index + 1 < values.count { event = values[index + 1]; index += 2 }
            else if value == "--port", index + 1 < values.count { port = Int(values[index + 1]) ?? port; index += 2 }
            else if value == "--dry-run-report" { dryRunReport = true; index += 1 }
            else { index += 1 }
        }
    }
}

struct NormalizedReport: Codable {
    let source: String
    let state: String
    let session: String
    let cwd: String?
    let agent: String?
    let parentSession: String?
    let model: String?
    let task: String?
    let terminalSession: String?
    let terminalKind: String?
    let terminalEndpoint: String?
}

func string(_ root: [String: Any], _ keys: String...) -> String? {
    for key in keys {
        if let value = root[key] as? String, !value.isEmpty { return value }
    }
    return nil
}

func nestedString(_ root: [String: Any], object: String, key: String) -> String? {
    (root[object] as? [String: Any])?[key] as? String
}

func normalize(_ root: [String: Any], args: BridgeArguments) -> NormalizedReport {
    let provider = args.provider.lowercased()
    let event = args.event.isEmpty ? (string(root, "hook_event_name", "event", "type") ?? "") : args.event
    let tool = string(root, "tool_name", "toolName")
        ?? nestedString(root, object: "toolCall", key: "name")
    let lowerEvent = event.lowercased()
    let lowerTool = tool?.lowercased() ?? ""
    let error = string(root, "error", "error_message", "errorMessage")
    let termination = string(root, "terminationReason", "reason")?.lowercased()
    let notification = string(root, "notification_type", "notificationType")?.lowercased()
    let state: String
    if lowerEvent.contains("failure") || lowerEvent.contains("error") || error?.isEmpty == false
        || termination == "error" || termination == "max_steps_exceeded" {
        state = "error"
    } else if lowerEvent.contains("permission") || lowerEvent.contains("elicitation")
                || (lowerEvent == "notification" && ["permission_prompt", "idle_prompt", "elicitation_dialog"].contains(notification))
                || lowerTool == "ask_question" || lowerTool == "askuserquestion" || lowerTool == "ask_user" {
        state = "waiting"
    } else if lowerEvent.contains("userprompt") || lowerEvent.contains("preinvocation")
                || lowerEvent.contains("subagentstart") || lowerEvent == "session.created" {
        state = "thinking"
    } else if lowerEvent.contains("pretool") || lowerEvent.contains("beforetool")
                || lowerEvent.contains("beforeshell") || lowerEvent.contains("afterfileedit")
                || lowerEvent == "tool.execute.before" {
        state = "coding"
    } else if lowerEvent == "session.idle" || lowerEvent.contains("sessionend")
                || lowerEvent.contains("teammateidle") {
        state = "idle"
    } else if lowerEvent == "stop" || lowerEvent.contains("taskcompleted")
                || lowerEvent.contains("subagentstop") {
        let fullyIdle = root["fullyIdle"] as? Bool
        state = fullyIdle == false ? "coding" : "success"
    } else if lowerEvent.contains("posttool") || lowerEvent == "tool.execute.after" {
        state = "thinking"
    } else if lowerEvent.contains("sessionstart") { state = "idle" }
    else { state = "thinking" }

    let parent = string(root, "parent_session_id", "parentSessionId", "parentSession")
    let mainSession = string(root, "session_id", "sessionId", "conversationId", "conversation_id")
        ?? ProcessInfo.processInfo.environment["CLAUDE_SESSION_ID"]
        ?? "\(provider)-\(ProcessInfo.processInfo.processIdentifier)"
    let agentID = string(root, "agent_id", "agentId", "subagent_id", "subagentId")
    let session = agentID ?? mainSession
    let derivedParent = agentID == nil ? parent : (parent ?? mainSession)
    let workspacePaths = (root["workspacePaths"] as? [String])
        ?? (root["workspace_roots"] as? [String])
    let cwd = string(root, "cwd", "working_dir", "working_directory", "directory")
        ?? workspacePaths?.first
        ?? ProcessInfo.processInfo.environment["PWD"]
    let agent = string(root, "agent_type", "agentType", "agent_name", "agentName")
    let model = string(root, "model", "model_id", "modelId")
    // Do not forward raw prompts, command arguments, tool results, or diffs.
    let task = string(root, "task_name", "taskName", "task_title", "taskTitle")

    let source: String = switch provider {
    case "claude": "claude-code"
    case "antigravity", "agy": "antigravity-cli"
    case "copilot": "github-copilot"
    case "qwen": "qwen-code"
    default: provider
    }
    let environment = ProcessInfo.processInfo.environment
    let terminal: (kind: String?, session: String?, endpoint: String?) = if let id = environment["ITERM_SESSION_ID"] {
        ("iterm2", id, nil)
    } else if let id = environment["WEZTERM_PANE"] {
        ("wezterm", id, environment["WEZTERM_UNIX_SOCKET"])
    } else if let id = environment["KITTY_WINDOW_ID"] {
        ("kitty", id, environment["KITTY_LISTEN_ON"])
    } else if environment["TERM_PROGRAM"] == "vscode" {
        ("vscode", nil, nil)
    } else if environment["TERM_PROGRAM"]?.lowercased().contains("warp") == true
                || environment["WARP_IS_LOCAL_SHELL"] != nil {
        ("warp", nil, nil)
    } else {
        (nil, nil, nil)
    }
    return NormalizedReport(
        source: source, state: state, session: session, cwd: cwd,
        agent: agent, parentSession: derivedParent, model: model, task: task,
        terminalSession: terminal.session, terminalKind: terminal.kind,
        terminalEndpoint: terminal.endpoint)
}

func neutralOutput(provider: String, event: String) -> String {
    let provider = provider.lowercased()
    let event = event.lowercased()
    if provider == "antigravity" || provider == "agy" {
        if event == "pretooluse" { return #"{"decision":"allow"}"# }
        if event == "preinvocation" { return #"{"injectSteps":[]}"# }
        if event == "posttooluse" { return "{}" }
        if event == "stop" { return #"{"decision":"stop"}"# }
    }
    // For Claude, Codex, Copilot, and Qwen an empty object observes without
    // approving, denying, blocking, or mutating the provider's behavior.
    return "{}"
}

func post(_ report: NormalizedReport, port: Int) {
    guard let url = URL(string: "http://127.0.0.1:\(port)/state"),
          let body = try? JSONEncoder().encode(report) else { return }
    var request = URLRequest(url: url, timeoutInterval: 0.75)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { _, _, _ in semaphore.signal() }.resume()
    _ = semaphore.wait(timeout: .now() + 0.8)
}

let args = BridgeArguments(CommandLine.arguments)
let input = FileHandle.standardInput.readDataToEndOfFile()
let root = ((try? JSONSerialization.jsonObject(with: input)) as? [String: Any]) ?? [:]
let report = normalize(root, args: args)
if args.dryRunReport {
    FileHandle.standardOutput.write((try? JSONEncoder().encode(report)) ?? Data("{}".utf8))
} else {
    post(report, port: args.port)
    FileHandle.standardOutput.write(Data((neutralOutput(provider: args.provider, event: args.event) + "\n").utf8))
}
