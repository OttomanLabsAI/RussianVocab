import XCTest
@testable import VocabFolio

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

    /// FirebaseCore raises an uncatchable exception at launch on an app id it
    /// doesn't like, so the check that gates configure() must agree with it,
    /// and the bundled GoogleService-Info.plist must be there and pass.
    @MainActor func testFirebaseConfigurationPassesFirebaseCoreCheck() throws {
        XCTAssertTrue(CloudService.isValidAppID("1:768664756180:ios:f4a9a034038f22bb8fc041"))
        XCTAssertFalse(CloudService.isValidAppID("1:768664756180:web:10741fa6d33908d58fc041"), "the website's id")
        XCTAssertFalse(CloudService.isValidAppID("2:768664756180:ios:f4a9a034038f22bb8fc041"), "unknown version")
        XCTAssertFalse(CloudService.isValidAppID("1:abc:ios:f4a9a034038f22bb8fc041"), "project number")
        XCTAssertFalse(CloudService.isValidAppID("1:768664756180:ios:"), "empty hash")
        XCTAssertFalse(CloudService.isValidAppID("1:768664756180:ios:xyz"), "non-hex hash")
        XCTAssertFalse(CloudService.isValidAppID(""))
        let options = try XCTUnwrap(CloudService.loadOptions(), "GoogleService-Info.plist missing from the app bundle")
        XCTAssertTrue(CloudService.isValidAppID(options.googleAppID))
        XCTAssertEqual(options.projectID, "russianvocab-90261")
        XCTAssertEqual(options.bundleID, "com.ottomanlabs.vocabfolio")
    }

    func testListsDirectionAndAddedFilterSettingsMatchTheWebShape() throws {
        var s = Settings()
        s.lists = ["Week 4", "Travel"]; s.reverse = true; s.since = 7
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.lists, ["Week 4", "Travel"])
        XCTAssertTrue(back.reverse)
        XCTAssertEqual(back.since, 7)
        // exactly what the website writes
        let web = try JSONDecoder().decode(Settings.self, from: Data(#"{"group":"Week 4","lists":["Week 4"],"reverse":true,"since":1}"#.utf8))
        XCTAssertEqual(web.lists, ["Week 4"])
        XCTAssertTrue(web.reverse)
        XCTAssertEqual(web.since, 1)
        XCTAssertEqual(Settings().lists, [])
        XCTAssertFalse(Settings().reverse)
        XCTAssertEqual(Settings().since, 0)
    }

    func testTeacherSentWordsCarryTheSender() throws {
        let w = try JSONDecoder().decode(Word.self, from: Data(#"{"ru":"стол","en":"table","pos":"n","t":1,"by":"teacher@example.com"}"#.utf8))
        XCTAssertEqual(w.by, "teacher@example.com")
        let plain = try JSONDecoder().decode(Word.self, from: Data(#"{"ru":"стол","en":"table","pos":"n","by":""}"#.utf8))
        XCTAssertNil(plain.by)
    }

    @MainActor func testSavedLeavesTheStarterFileOut() {
        let starter: Set<String> = ["вода|n"]
        XCTAssertFalse(AppStore.isSaved(Word(ru: "вода", en: "water", pos: "n"), starterKeys: starter), "starter word, untouched")
        XCTAssertTrue(AppStore.isSaved(Word(ru: "вода", en: "water", pos: "n", t: 1), starterKeys: starter), "re-added later → saved")
        XCTAssertTrue(AppStore.isSaved(Word(ru: "стол", en: "table", pos: "n"), starterKeys: starter), "not a starter word")
        XCTAssertFalse(AppStore.starterKeys.isEmpty, "the bundled starter file loads")
    }

    func testQuizDealsFiveDistinctChoicesWithOneAnswer() {
        let words = [
            Word(ru: "стол", en: "table", pos: "n"), Word(ru: "стул", en: "chair", pos: "n"),
            Word(ru: "окно", en: "window", pos: "n"), Word(ru: "дверь", en: "door", pos: "n"),
            Word(ru: "идти", en: "to go", pos: "v"), Word(ru: "кофе", en: "coffee", pos: "n"),
            Word(ru: "чай", en: "tea", pos: "n"), Word(ru: "Стол", en: "table", pos: "n"),   // same text, must not duplicate
        ]
        for _ in 0..<20 {
            let opts = AppStore.quizOptions(for: words[0], words: words, dictionary: [], reverse: false)
            XCTAssertEqual(opts.count, 5)
            XCTAssertEqual(opts.filter(\.correct).count, 1)
            XCTAssertEqual(opts.first { $0.correct }?.text, "table")
            XCTAssertEqual(Set(opts.map { $0.text.lowercased() }).count, 5, "no two choices read the same")
            XCTAssertFalse(opts.contains { $0.text == "to go" }, "nouns fill the choices before the verb is needed")
        }
        let ru = AppStore.quizOptions(for: words[0], words: words, dictionary: [], reverse: true)
        XCTAssertEqual(ru.first { $0.correct }?.text, "стол")
        XCTAssertTrue(ru.allSatisfy { Translit.containsCyrillic($0.text) }, "reversed quiz offers Russian")
        // Too few words: the dictionary fills in.
        let few = AppStore.quizOptions(for: words[0], words: [words[0]], dictionary: [], reverse: false)
        XCTAssertEqual(few.count, 1, "nothing to fill with gives just the answer")
    }

    func testAddedFilterCutsAtLocalMidnight() {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now).timeIntervalSince1970 * 1000
        XCTAssertEqual(AppStore.sinceCutoff(days: 1, now: now), midnight)
        XCTAssertEqual(AppStore.sinceCutoff(days: 7, now: now), midnight - 6 * 86_400_000)
        XCTAssertNil(AppStore.sinceCutoff(days: 0, now: now))
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

    func testLanguageChoiceIsReadFromSettingsAndValidated() throws {
        let json = #"{"group":"Food","native":"en","learning":"ru"}"#
        var settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.native, "en")
        XCTAssertEqual(settings.learning, "ru")
        XCTAssertTrue(Languages.isSupported(native: settings.native, learning: settings.learning))
        XCTAssertEqual(Languages.pairLabel(native: settings.native, learning: settings.learning), "English → Русский")

        XCTAssertEqual(Languages.nativeOptions.map(\.code), ["en"])
        XCTAssertEqual(Languages.learningOptions(for: "en").map(\.code), ["ru"])
        XCTAssertTrue(Languages.learningOptions(for: "ru").isEmpty)
        XCTAssertFalse(Languages.isSupported(native: "ru", learning: "en"))
        XCTAssertFalse(Languages.isSupported(native: nil, learning: nil))
        XCTAssertEqual(Languages.pairLabel(native: nil, learning: nil), "Choose your languages")

        settings.learning = nil
        XCTAssertNil(settings.learning)
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        XCTAssertEqual(saved?["native"] as? String, "en")
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
