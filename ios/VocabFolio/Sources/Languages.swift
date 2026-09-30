import Foundation

struct Language: Identifiable, Equatable, Sendable {
    let code: String
    let name: String       // in English
    let selfName: String   // in the language itself
    var id: String { code }
}

/// Language pairs that have a dictionary behind them — the same list the
/// website offers. Onboarding shows only these, so adding a language is one
/// entry here plus its data.
enum Languages {
    static let all: [String: Language] = [
        "en": Language(code: "en", name: "English", selfName: "English"),
        "ru": Language(code: "ru", name: "Russian", selfName: "Русский"),
    ]
    /// (the learner's language, the language learned)
    static let pairs: [(native: String, learning: String)] = [("en", "ru")]

    static var nativeOptions: [Language] {
        var seen: [String] = []
        for p in pairs where !seen.contains(p.native) { seen.append(p.native) }
        return seen.compactMap { all[$0] }
    }

    static func learningOptions(for native: String) -> [Language] {
        pairs.filter { $0.native == native }.compactMap { all[$0.learning] }
    }

    static func isSupported(native: String?, learning: String?) -> Bool {
        pairs.contains { $0.native == native && $0.learning == learning }
    }

    /// "English → Русский", or a prompt when nothing is chosen yet.
    static func pairLabel(native: String?, learning: String?) -> String {
        guard isSupported(native: native, learning: learning),
              let n = all[native ?? ""], let l = all[learning ?? ""] else { return "Choose your languages" }
        return "\(n.name) → \(l.selfName)"
    }
}
