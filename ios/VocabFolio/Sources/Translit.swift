import Foundation

/// Cyrillic helpers ported one-to-one from the web app, so pronunciations
/// generated on either platform come out identical.
enum Translit {
    static let vowels: Set<Character> = ["а", "е", "ё", "и", "о", "у", "ы", "э", "ю", "я"]
    static let map: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh", "з": "z",
        "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s",
        "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "",
        "ы": "y", "ь": "'", "э": "e", "ю": "yu", "я": "ya",
    ]

    /// Strips stress marks (apostrophe convention and combining acute).
    static func bare(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{0301}", with: "")
    }

    /// `вода'` → `вода́` (apostrophe after a vowel becomes a combining acute).
    static func acuteize(_ s: String) -> String {
        var out = ""
        var prev: Character? = nil
        for ch in s {
            if ch == "'", let p = prev, vowels.contains(Character(String(p).lowercased())) {
                out.append("\u{0301}")
            } else {
                out.append(ch)
            }
            prev = ch
        }
        return out
    }

    /// Letter-for-letter Latin form used for keyboard-free search (вода → voda).
    static func plainLat(_ s: String) -> String {
        var t = ""
        for ch in s.lowercased() { t += map[ch] ?? String(ch) }
        return t.replacingOccurrences(of: "'", with: "")
    }

    static func containsCyrillic(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    /// Syllabified pronunciation with the stressed syllable in capitals,
    /// e.g. `вода'` → `va-DA`... (the web app's `translitWord`).
    static func word(_ w: String) -> String {
        var stress = -1
        var letters: [Character] = []
        for ch in w {
            if ch == "'" || ch == "\u{0301}" { stress = letters.count - 1; continue }
            letters.append(ch)
        }
        let lower = letters.map { Character(String($0).lowercased()) }
        let isV = lower.map { vowels.contains($0) }
        if stress < 0, let yo = lower.firstIndex(of: "ё") { stress = yo }
        var vIdx: [Int] = []
        for (i, v) in isV.enumerated() where v { vIdx.append(i) }
        var syl = [Int](repeating: 0, count: lower.count)
        if vIdx.count > 1 {
            for s in 1..<vIdx.count {
                let prevV = vIdx[s - 1], thisV = vIdx[s]
                var boundary = thisV
                if thisV - prevV > 1 { boundary = thisV - 1 }
                while boundary < thisV && (lower[boundary] == "ь" || lower[boundary] == "ъ") { boundary += 1 }
                if boundary < lower.count {
                    for i in boundary..<lower.count { syl[i] = s }
                }
            }
        }
        let nSyl = max(vIdx.count, 1)
        let stressSyl = stress >= 0 && stress < syl.count ? syl[stress] : (nSyl == 1 ? 0 : -1)
        var parts: [String] = []
        for s in 0..<nSyl {
            var t = ""
            for i in 0..<lower.count where syl[i] == s {
                var lat = map[lower[i]] ?? String(letters[i])
                if lower[i] == "е" && (i == 0 || isV[i - 1] || lower[i - 1] == "ь" || lower[i - 1] == "ъ") {
                    lat = "ye"
                }
                t += lat
            }
            parts.append(nSyl > 1 && s == stressSyl ? t.uppercased() : t)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "-")
    }

    static func pronunciation(_ ac: String) -> String {
        ac.split(separator: " ").map { word(String($0)) }.joined(separator: " ")
    }
}
