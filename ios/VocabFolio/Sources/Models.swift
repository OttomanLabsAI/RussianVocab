import Foundation

// MARK: - Wire-compatible models
// These mirror the JSON the web app stores in Firestore and localStorage
// exactly, so one account reads identically on both platforms.

/// A JSON value that survives round-trips untouched — used for settings so
/// keys this build doesn't know about are never dropped on save.
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        default: return nil
        }
    }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
}

/// Compact FSRS card state as stored on each word (`c`). A word with no `c`
/// is a new card — that rule is what makes old word files need no migration.
struct CardData: Codable, Equatable {
    var d: Double   = 0   // due, epoch ms
    var sb: Double  = 0   // stability
    var df: Double  = 0   // difficulty
    var ed: Double  = 0   // elapsed days
    var sd: Double  = 0   // scheduled days
    var r: Double   = 0   // reps
    var l: Double   = 0   // lapses
    var s: Double   = 0   // state: 0 new · 1 learning · 2 review · 3 relearning
    var ls: Double  = 0   // learning step index
    var lr: Double  = 0   // last review, epoch ms (0 = never)

    var state: Int { Int(s) }
    var isNew: Bool { state == 0 }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        d  = try c.decodeIfPresent(Double.self, forKey: .d)  ?? 0
        sb = try c.decodeIfPresent(Double.self, forKey: .sb) ?? 0
        df = try c.decodeIfPresent(Double.self, forKey: .df) ?? 0
        ed = try c.decodeIfPresent(Double.self, forKey: .ed) ?? 0
        sd = try c.decodeIfPresent(Double.self, forKey: .sd) ?? 0
        r  = try c.decodeIfPresent(Double.self, forKey: .r)  ?? 0
        l  = try c.decodeIfPresent(Double.self, forKey: .l)  ?? 0
        s  = try c.decodeIfPresent(Double.self, forKey: .s)  ?? 0
        ls = try c.decodeIfPresent(Double.self, forKey: .ls) ?? 0
        lr = try c.decodeIfPresent(Double.self, forKey: .lr) ?? 0
    }
}

/// Parts of speech, in tab order, with English and Russian names.
enum PartOfSpeech {
    static let order = ["n", "v", "a", "d", "r", "p", "c", "t", "m", "e", "o"]
    static let names: [String: (en: String, ru: String)] = [
        "n": ("Nouns", "Существительные"), "v": ("Verbs", "Глаголы"),
        "a": ("Adjectives", "Прилагательные"), "d": ("Adverbs", "Наречия"),
        "r": ("Pronouns", "Местоимения"), "p": ("Prepositions", "Предлоги"),
        "c": ("Conjunctions", "Союзы"), "t": ("Particles", "Частицы"),
        "m": ("Numerals", "Числительные"), "e": ("Expressions", "Выражения"),
        "o": ("Other", "Разное"),
    ]
    static func isValid(_ pos: String) -> Bool { names[pos] != nil }
    static func english(_ pos: String) -> String { names[pos]?.en ?? "Other" }
    static func russian(_ pos: String) -> String { names[pos]?.ru ?? "Разное" }
}

struct Word: Codable, Equatable, Identifiable {
    var ru: String
    var ac: String = ""
    var pr: String = ""
    var en: String
    var pos: String
    var g: String = "My additions"
    var x: String = ""
    var t: Double? = nil       // added-at, epoch ms
    var c: CardData? = nil     // FSRS card state
    var by: String? = nil      // who sent it (a teacher's email), if anyone

    /// Same identity rule as the web app: bare word + part of speech.
    var key: String { Translit.bare(ru).lowercased() + "|" + pos }
    var id: String { key }
    var display: String { ac.isEmpty ? ru : Translit.acuteize(ac) }
    var group: String { g.isEmpty ? "Ungrouped" : g }
    var addedAt: Date? { t.map { Date(timeIntervalSince1970: $0 / 1000) } }

    /// Gender / aspect extra, rendered like the web app's `extraText`.
    var extraText: String {
        guard !x.isEmpty else { return "" }
        if pos == "n" { return "(\(x))" }
        if pos == "v" {
            let parts = x.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            var t = parts.first == "p" ? "pf" : "impf"
            if parts.count > 1, !parts[1].isEmpty { t += " · pair: " + parts[1] }
            return "(\(t))"
        }
        return ""
    }

    init(ru: String, ac: String = "", pr: String = "", en: String, pos: String,
         g: String = "My additions", x: String = "", t: Double? = nil, c: CardData? = nil,
         by: String? = nil) {
        self.ru = ru; self.ac = ac; self.pr = pr; self.en = en; self.pos = pos
        self.g = g; self.x = x; self.t = t; self.c = c; self.by = by
    }

    enum CodingKeys: String, CodingKey { case ru, ac, pr, en, pos, g, x, t, c, by }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        ru  = try k.decode(String.self, forKey: .ru)
        en  = try k.decode(String.self, forKey: .en)
        pos = try k.decode(String.self, forKey: .pos)
        ac  = try k.decodeIfPresent(String.self, forKey: .ac) ?? ""
        pr  = try k.decodeIfPresent(String.self, forKey: .pr) ?? ""
        g   = try k.decodeIfPresent(String.self, forKey: .g) ?? "My additions"
        x   = try k.decodeIfPresent(String.self, forKey: .x) ?? ""
        t   = (try? k.decodeIfPresent(Double.self, forKey: .t)) ?? nil
        c   = (try? k.decodeIfPresent(CardData.self, forKey: .c)) ?? nil
        by  = (try? k.decodeIfPresent(String.self, forKey: .by)) ?? nil
        if by?.isEmpty == true { by = nil }
    }

    var isValid: Bool { !ru.isEmpty && PartOfSpeech.isValid(pos) }
}

/// Settings keep every key the web app might store; typed accessors for ours.
struct Settings: Codable, Equatable {
    var raw: [String: JSONValue]

    init(raw: [String: JSONValue] = ["group": .string("My additions")]) { self.raw = raw }
    init(from decoder: Decoder) throws {
        raw = (try? decoder.singleValueContainer().decode([String: JSONValue].self)) ?? [:]
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }

    var group: String {
        get { let g = raw["group"]?.stringValue ?? ""; return g.isEmpty ? "My additions" : g }
        set { raw["group"] = .string(newValue) }
    }
    var newPerDay: Int {
        get { max(0, Int(raw["newPerDay"]?.doubleValue ?? 20)) }
        set { raw["newPerDay"] = .number(Double(newValue)) }
    }
    var introDay: String? {
        get { raw["introDay"]?.stringValue }
        set { raw["introDay"] = newValue.map { .string($0) } ?? .null }
    }
    var introCount: Int {
        get { Int(raw["introCount"]?.doubleValue ?? 0) }
        set { raw["introCount"] = .number(Double(newValue)) }
    }
    var autoSay: Bool {
        get { raw["autoSay"]?.boolValue ?? false }
        set { raw["autoSay"] = .bool(newValue) }
    }
    var deck: String? {
        get { let d = raw["deck"]?.stringValue ?? ""; return d.isEmpty ? nil : d }
        set { raw["deck"] = .string(newValue ?? "") }
    }
    /// The language the learner speaks, e.g. "en".
    var native: String? {
        get { let v = raw["native"]?.stringValue ?? ""; return v.isEmpty ? nil : v }
        set { raw["native"] = .string(newValue ?? "") }
    }
    /// The language being learned, e.g. "ru".
    var learning: String? {
        get { let v = raw["learning"]?.stringValue ?? ""; return v.isEmpty ? nil : v }
        set { raw["learning"] = .string(newValue ?? "") }
    }
    /// Lists the learner created and kept, so an empty one survives until deleted.
    var lists: [String] {
        get { (raw["lists"]?.arrayValue ?? []).compactMap(\.stringValue).filter { !$0.isEmpty } }
        set { raw["lists"] = .array(newValue.map { .string($0) }) }
    }
    /// Flashcards show the English first and ask for the Russian.
    var reverse: Bool {
        get { raw["reverse"]?.boolValue ?? false }
        set { raw["reverse"] = .bool(newValue) }
    }
    /// Review only words added in the last N days (1 = today); 0 = any time.
    var since: Int {
        get { max(0, Int(raw["since"]?.doubleValue ?? 0)) }
        set { raw["since"] = .number(Double(max(0, newValue))) }
    }

    mutating func merge(_ other: Settings) {
        for (k, v) in other.raw { raw[k] = v }
    }
}

struct DayStat: Codable, Equatable {
    var n: Int = 0   // reviews
    var a: Int = 0   // marked Again
    init(n: Int = 0, a: Int = 0) { self.n = n; self.a = a }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = Int(try c.decodeIfPresent(Double.self, forKey: .n) ?? 0)
        a = Int(try c.decodeIfPresent(Double.self, forKey: .a) ?? 0)
    }
}

/// Daily review aggregates (`stats.days` on the user doc), keyed YYYYMMDD.
struct Stats: Codable, Equatable {
    var days: [String: DayStat] = [:]
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = (try? c.decodeIfPresent([String: DayStat].self, forKey: .days)) ?? [:]
    }
    enum CodingKeys: String, CodingKey { case days }

    /// History is additive: merging keeps the larger count for each day.
    static func merge(_ a: Stats, _ b: Stats) -> Stats {
        var out = Stats()
        for s in [a, b] {
            for (k, v) in s.days {
                let cur = out.days[k] ?? DayStat()
                out.days[k] = DayStat(n: max(cur.n, v.n), a: max(cur.a, v.a))
            }
        }
        return out
    }
    /// The day a YYYYMMDD key names, at local midnight.
    static func date(from key: String) -> Date? {
        guard key.count == 8, let y = Int(key.prefix(4)), let m = Int(key.dropFirst(4).prefix(2)),
              let d = Int(key.suffix(2)) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
    }

    static func key(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    mutating func bump(again: Bool, at date: Date = Date()) {
        let k = Stats.key(for: date)
        var e = days[k] ?? DayStat()
        e.n += 1
        if again { e.a += 1 }
        days[k] = e
    }
}

/// One review-log entry, exactly what the web app appends.
struct LogEntry: Codable, Equatable {
    var w: String      // word key
    var r: Int         // rating 1–4
    var at: Double     // epoch ms
    var el: Double     // elapsed days
    var sc: Double     // scheduled days
    var st: Int        // state before the review
}

/// Everything persisted on-device between launches.
struct LocalState: Codable {
    var v: Int = 1
    var words: [Word] = []
    var settings = Settings()
    var stats = Stats()
    var syncHash: String = ""
    var pendingLog: [LogEntry] = []
}

enum WordHash {
    /// Stable fingerprint of a word list, used to detect "unchanged since sync".
    /// Only ever compared with hashes made on this same device.
    static func of(_ words: [Word]) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = (try? enc.encode(words)) ?? Data()
        var h: UInt32 = 5381
        for b in data { h = (h &<< 5) &+ h &+ UInt32(b) }
        return "\(h):\(words.count)"
    }
}
