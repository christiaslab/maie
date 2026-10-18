import Foundation

// Teaching guidance adapted from Matt Pocock's wait-what and teach skills.
// See ../THIRD-PARTY-NOTICES.md for sources and the upstream MIT notice.
enum DiscussionGuidance {
    // Native inline styling only: preserve line breaks and never activate model links.
    static func displayText(_ source: String) -> AttributedString {
        var text = (try? AttributedString(markdown: source, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        for run in text.runs where run.link != nil {
            text[run.range].link = nil
        }
        return text
    }

    static let explain = DiscussionSkills.explain
    static let teach = DiscussionSkills.teach

    static let instructions = """
    DISCUSSION GUIDANCE
    Follow the human's current request naturally, in their language, without announcing a mode or skill. Keep ordinary follow-ups brief. Use EXPLAIN for confusion and TEACH for an explicit request for deeper learning; use the recent discussion only to interpret a follow-up, not to override a changed request. Introduce only the detail needed for the current step. A continuation question is an invitation to proceed, not a quiz: offer exercises or understanding checks only when requested. State uncertainty and distinguish examples from known project facts. Describe only sources actually present in the provided context; you have no browsing or research tools. Keep the human's own decisions and final answer separate from your explanation. Learning preferences and progress are not tracked outside this conversation, and you cannot create lessons, files, or learning records.

    \(explain)

    \(teach)
    """
}
