import XCTest
@testable import RusVocab

/// Wire-format and transliteration parity with the web app. The expected
/// pronunciations were produced by the website's own JavaScript.
final class ModelTests: XCTestCase {
    func testTransliterationMatchesWebApp() {
        let samples: [(ac: String, bare: String, acute: String, pr: String, lat: String)] = [
            ("вода'", "вода", "вода\u{0301}", "vo-DA", "voda"),
            ("кни'га", "книга", "кни\u{0301}га", "KNI-ga", "kniga"),
            ("челове'к", "человек", "челове\u{0301}к", "che-lo-VEK", "chelovek"),
            ("я", "я", "я", "ya", "ya"),
            ("ребёнок", "ребёнок", "ребёнок", "re-BYO-nok", "rebyonok"),
            ("здра'вствуйте", "здравствуйте", "здра\u{0301}вствуйте", "ZDRAVST-vuy-te", "zdravstvuyte"),
            ("семья'", "семья", "семья\u{0301}", "sem'-YA", "semya"),
            ("объе'кт", "объект", "объе\u{0301}кт", "ob-YEKT", "obekt"),
            ("ёлка", "ёлка", "ёлка", "YOL-ka", "yolka"),
            ("по'сле", "после", "по\u{0301}сле", "POS-le", "posle"),
            ("до свида'ния", "до свидания", "до свида\u{0301}ния", "do svi-DA-ni-ya", "do svidaniya"),
            ("может быть", "может быть", "может быть", "mo-zhet byt'", "mozhet byt"),
            ("стол", "стол", "стол", "stol", "stol"),
        ]
        for s in samples {
            XCTAssertEqual(Translit.bare(s.ac), s.bare, s.ac)
            XCTAssertEqual(Translit.acuteize(s.ac), s.acute, s.ac)
            XCTAssertEqual(Translit.pronunciation(s.ac), s.pr, s.ac)
            XCTAssertEqual(Translit.plainLat(Translit.bare(s.ac)), s.lat, s.ac)
        }
    }

    func testWordDecodesWebFormatAndKeepsUnknownSettings() throws {
        let json = """
        {"words":[{"ru":"вода","ac":"вода'","pr":"vo-DA","en":"water","pos":"n","g":"Food","x":"f","t":1758112345678,
                   "c":{"d":1758200000000,"sb":2.3,"df":5.1,"ed":0,"sd":2,"r":1,"l":0,"s":2,"ls":0,"lr":1758112345678}},
                  {"ru":"стол","en":"table","pos":"n"},
                  {"ru":"bad","en":"no pos","pos":"zz"}],
         "settings":{"group":"Food","newPerDay":15,"autoSay":true,"deck":"Food","futureKey":{"nested":1}},
         "stats":{"days":{"20260917":{"n":12,"a":3}}}}
        """
        struct Blob: Decodable { let words: [Word]; let settings: Settings; let stats: Stats }
        let blob = try JSONDecoder().decode(Blob.self, from: Data(json.utf8))
        let valid = blob.words.filter(\.isValid)
        XCTAssertEqual(valid.count, 2)
        XCTAssertEqual(valid[0].key, "вода|n")
        XCTAssertEqual(valid[0].display, "вода\u{0301}")
        XCTAssertEqual(valid[0].c?.state, 2)
        XCTAssertEqual(valid[0].c?.sd, 2)
        XCTAssertNil(valid[1].c, "a word without c is a new card")
        XCTAssertEqual(valid[1].g, "My additions")
        XCTAssertEqual(blob.settings.group, "Food")
        XCTAssertEqual(blob.settings.newPerDay, 15)
        XCTAssertTrue(blob.settings.autoSay)
        XCTAssertEqual(blob.settings.deck, "Food")
        XCTAssertEqual(blob.stats.days["20260917"]?.n, 12)

        // Unknown keys survive a save round-trip.
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blob.settings)) as? [String: Any]
        XCTAssertNotNil(reencoded?["futureKey"])

        // Encoded words omit absent optionals, as the web app does.
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid[1])) as? [String: Any]
        XCTAssertNil(encoded?["t"])
        XCTAssertNil(encoded?["c"])
    }

    func testStatsMergeKeepsTheLargerCount() {
        var a = Stats(); a.days["20260916"] = DayStat(n: 5, a: 1); a.days["20260917"] = DayStat(n: 2, a: 0)
        var b = Stats(); b.days["20260917"] = DayStat(n: 9, a: 4); b.days["20260918"] = DayStat(n: 1, a: 0)
        let m = Stats.merge(a, b)
        XCTAssertEqual(m.days["20260916"]?.n, 5)
        XCTAssertEqual(m.days["20260917"]?.n, 9)
        XCTAssertEqual(m.days["20260917"]?.a, 4)
        XCTAssertEqual(m.days["20260918"]?.n, 1)
    }

    @MainActor func testShareCodesUseTheUnambiguousAlphabet() {
        for _ in 0..<200 {
            let code = AppStore.generateCode()
            XCTAssertEqual(code.count, 7)
            XCTAssertTrue(code.allSatisfy { "ABCDEFGHJKMNPQRSTUVWXYZ23456789".contains($0) }, code)
        }
    }
}
