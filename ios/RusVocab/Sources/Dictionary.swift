import Foundation

/// One dictionary entry from dict.json: `[accented, english, pos, extra]`,
/// ordered by frequency (index = rank).
struct DictEntry: Identifiable, Equatable {
    let id: Int
    let ac: String
    let en: String
    let pos: String
    let x: String
    let bareLower: String
    let enLower: String
    let lat: String

    var display: String { Translit.acuteize(ac) }
    var bare: String { Translit.bare(ac) }
    var pronunciation: String { Translit.pronunciation(ac) }
    var key: String { bareLower + "|" + pos }
    var rank: Int { id + 1 }

    static func == (a: DictEntry, b: DictEntry) -> Bool { a.id == b.id }
}

/// The bundled OpenRussian dictionary with the web app's search ranking.
@MainActor
final class RuDictionary: ObservableObject {
    @Published private(set) var entries: [DictEntry] = []
    @Published private(set) var ready = false

    func load() {
        guard !ready, entries.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            let built = RuDictionary.parse()
            await MainActor.run {
                self.entries = built
                self.ready = true
            }
        }
    }

    nonisolated private static func parse() -> [DictEntry] {
        guard let url = Bundle.main.url(forResource: "dict", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return [] }
        var out: [DictEntry] = []
        out.reserveCapacity(raw.count)
        for (i, row) in raw.enumerated() where row.count >= 3 {
            let ac = row[0]
            let bare = Translit.bare(ac).lowercased()
            out.append(DictEntry(id: i, ac: ac, en: row[1], pos: row[2],
                                 x: row.count > 3 ? row[3] : "",
                                 bareLower: bare, enLower: row[1].lowercased(),
                                 lat: Translit.plainLat(bare)))
        }
        return out
    }

    /// Same ranking as the web app: exact/prefix English, then Latin-typed
    /// Russian prefixes, then word-boundary English, then substrings.
    nonisolated static func search(_ raw: String, in entries: [DictEntry]) -> [DictEntry] {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        let cyr = Translit.containsCyrillic(q)
        let qLat = q.replacingOccurrences(of: "'", with: "")
        var starts: [DictEntry] = [], latStarts: [DictEntry] = [], subs: [DictEntry] = []
        var latSubs: [DictEntry] = [], enHits: [DictEntry] = []
        for e in entries {
            if cyr {
                if e.bareLower.hasPrefix(q) { starts.append(e) }
                else if e.bareLower.contains(q) { subs.append(e) }
            } else {
                let en = e.enLower
                if en == q || en.hasPrefix(q + ",") || en.hasPrefix(q + ";") { starts.append(e) }
                else if e.lat.hasPrefix(qLat) { latStarts.append(e) }
                else if (" " + en).contains(" " + q) { subs.append(e) }
                else if e.lat.contains(qLat) { latSubs.append(e) }
                else if en.contains(q) { enHits.append(e) }
            }
            if starts.count > 400 { break }
        }
        return Array((starts + latStarts + subs + latSubs + enHits).prefix(60))
    }
}
