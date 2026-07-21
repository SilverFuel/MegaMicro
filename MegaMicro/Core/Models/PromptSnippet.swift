import Foundation

/// A reusable prompt template. Snippets stay local in AppConfig and are copied
/// to the clipboard explicitly; MegaMicro never submits them to an agent.
struct PromptSnippet: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var prompt: String
    var builtIn: Bool

    func rendered(with values: [String: String]) -> String {
        values.filter { !$0.value.isEmpty }.reduce(prompt) { result, entry in
            result.replacingOccurrences(of: "{{\(entry.key)}}", with: entry.value)
        }
    }
}

enum DefaultPromptSnippets {
    static let planner = PromptSnippet(
        id: "parallel-planner",
        name: "Parallel Planner",
        prompt: """
        You are the planning agent for a parallel implementation effort.

        Request:
        {{request}}

        Project:
        {{project}}

        Analyze the existing codebase and the full request before proposing changes. Identify work that can be implemented independently and work that must remain sequential. Create a planning folder in the repository containing:

        1. A master plan describing the architecture, shared constraints, dependencies, risks, and verification strategy.
        2. One self-contained subplan for each parallel track. Give every track explicit scope, owned files or components, required interfaces, acceptance criteria, and anything it must not change.
        3. An integration plan for the final agent explaining the expected outputs, merge order, cross-track checks, likely conflicts, migrations, and final tests.

        Minimize overlap between tracks. If two tracks would edit the same central file, define the shared contract first or make one track responsible for that file. Do not implement the feature yourself; produce instructions that implementation agents can follow without needing to rediscover the overall plan.
        """,
        builtIn: true)

    static let worker = PromptSnippet(
        id: "parallel-worker",
        name: "Parallel Worker",
        prompt: """
        You are one implementation agent in a parallelized project.

        Project:
        {{project}}

        Assigned track:
        {{track}}

        Plan location:
        {{plan_path}}

        Read the master plan and your assigned subplan, then implement only that track. Treat the documented interfaces and boundaries as contracts. Do not redesign unrelated areas, take ownership of another track, or make speculative cleanup changes outside your scope.

        If you discover a cross-track issue, document it clearly for the integration agent instead of silently expanding your assignment. Run the focused tests appropriate to your work. When finished, summarize the files changed, behavior implemented, tests run, assumptions made, and any integration notes or unresolved risks.
        """,
        builtIn: true)

    static let integrator = PromptSnippet(
        id: "parallel-integrator",
        name: "Final Integrator",
        prompt: """
        You are the final integration agent for a parallel implementation effort.

        Original request:
        {{request}}

        Project:
        {{project}}

        Plan location:
        {{plan_path}}

        Review the master plan, every track plan, the integration instructions, and all completed track work before changing code. Combine the tracks into one coherent implementation. Resolve conflicts according to the intended architecture rather than merely choosing one side, and check that shared interfaces, configuration migrations, documentation, and user-facing behavior agree across tracks.

        Run the complete relevant test and build suite, fix integration defects, and verify the original request end to end. Avoid unrelated refactoring. Finish with a concise summary of the integrated result, conflicts or gaps you resolved, verification performed, and any remaining risks.
        """,
        builtIn: true)

    static let all = [planner, worker, integrator]

    static func snippet(id: String) -> PromptSnippet? {
        all.first { $0.id == id }
    }
}
