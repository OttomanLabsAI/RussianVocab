import Foundation
import FirebaseAuth
import FSRS

enum CloudError: LocalizedError {
    case signedOut
    case unconfigured
    var errorDescription: String? {
        switch self {
        case .signedOut: return "Sign in to do that."
        case .unconfigured: return "Accounts aren't available in this build — words stay on this device."
        }
    }
}

/// The app's single source of truth: the word file, settings, review stats,
/// the account, and the same local-first sync rules the web app uses.
@MainActor
final class AppStore: ObservableObject {
    @Published var words: [Word] = []
    @Published var settings = Settings()
    @Published var stats = Stats()
    @Published var account: Account?
    @Published var status = "auto-saves on this device"
    @Published var conflict: CloudSnapshot?
    @Published private(set) var dueTotal = 0

    private(set) var pendingLog: [LogEntry] = []
    private var syncHash = ""
    private var cloudChunks = 0
    private var cloudBusy = false
    private var cloudDirty = false
    private var localTask: Task<Void, Never>?
    private var cloudTask: Task<Void, Never>?
    private var logTask: Task<Void, Never>?
    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        if let saved = Persistence.load() {
            words = saved.words.filter(\.isValid)
            settings = saved.settings
            stats = saved.stats
            syncHash = saved.syncHash
            pendingLog = saved.pendingLog
        } else {
            words = Persistence.starterWords()
            // A freshly seeded device counts as "unchanged since sync", so signing
            // in adopts the account silently instead of asking which file to keep.
            syncHash = WordHash.of(words)
        }
        recount()
    }

    func start() {
        CloudService.shared.configure()
        // Without a usable Firebase configuration the app is device-only; the
        // account box says so instead of the app dying at launch.
        guard CloudService.shared.isConfigured else {
            status = "accounts unavailable in this build — saving on this device"
            return
        }
        authHandle = CloudService.shared.listen { [weak self] acct in
            Task { @MainActor in await self?.handleAuth(acct) }
        }
    }

    // MARK: Words

    var keys: Set<String> { Set(words.map(\.key)) }

    var groups: [String] {
        var seen: [String] = []
        for w in words where !seen.contains(w.group) { seen.append(w.group) }
        return seen
    }

    func has(_ key: String) -> Bool { words.contains { $0.key == key } }

    func word(for key: String) -> Word? { words.first { $0.key == key } }

    func add(_ entry: DictEntry) {
        guard !has(entry.key) else { return }
        words.append(Word(ru: entry.bare, ac: entry.ac, pr: entry.pronunciation, en: entry.en,
                          pos: entry.pos, g: settings.group, x: entry.x,
                          t: Date().timeIntervalSince1970 * 1000))
        changed()
    }

    func remove(_ key: String) {
        words.removeAll { $0.key == key }
        changed()
    }

    func setGroup(_ g: String) {
        let name = g.trimmingCharacters(in: .whitespaces)
        settings.group = name.isEmpty ? "My additions" : name
        changed()
    }

    func setDeck(_ deck: String?) {
        settings.deck = deck
        changed()
    }

    func setNewPerDay(_ n: Int) {
        settings.newPerDay = min(500, max(0, n))
        changed()
    }

    func setAutoSay(_ on: Bool) {
        settings.autoSay = on
        changed()
    }

    // MARK: Languages

    /// True once the learner has picked a supported pair; until then the
    /// onboarding covers the app.
    var hasLanguages: Bool { Languages.isSupported(native: settings.native, learning: settings.learning) }

    /// Set when the learner reopens the language picker from Account.
    @Published var editingLanguages = false

    func setLanguages(native: String, learning: String) {
        settings.native = native
        settings.learning = learning
        editingLanguages = false
        changed()            // saved locally and, when signed in, to the account
    }

    private func changed() {
        recount()
        scheduleSave()
    }

    // MARK: Persistence and sync

    private func persistLocal() {
        Persistence.save(LocalState(v: 1, words: words, settings: settings, stats: stats,
                                    syncHash: syncHash, pendingLog: pendingLog))
    }

    func scheduleSave() {
        localTask?.cancel()
        localTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persistLocal()
        }
        guard account != nil else { return }
        cloudTask?.cancel()
        cloudTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await self?.pushCloud()
        }
    }

    /// Called when the app goes to the background — nothing waits on a timer.
    func flushSave() {
        localTask?.cancel()
        persistLocal()
        if account != nil {
            cloudTask?.cancel()
            Task { await pushCloud() }
        }
        flushLog()
    }

    func pushCloud() async {
        guard let a = account else { return }
        if cloudBusy { cloudDirty = true; return }
        cloudBusy = true
        status = "saving to account…"
        do {
            cloudChunks = try await CloudService.shared.saveCloud(
                uid: a.uid, words: words, settings: settings, prevChunks: cloudChunks, stats: stats)
            syncHash = WordHash.of(words)
            persistLocal()
            status = "saved to account ✓"
        } catch {
            status = "cloud save failed — kept on this device"
        }
        cloudBusy = false
        if cloudDirty { cloudDirty = false; await pushCloud() }
    }

    // MARK: Account

    private func handleAuth(_ acct: Account?) async {
        account = acct
        guard let a = acct else { status = "auto-saves on this device"; return }
        status = "loading your account…"
        do {
            let cloud = try await CloudService.shared.loadCloud(uid: a.uid)
            // Review history is additive: merge it whichever word file wins.
            if let cloud { stats = Stats.merge(stats, cloud.stats) }
            if let cloud, !cloud.words.isEmpty {
                cloudChunks = cloud.chunks
                let localHash = WordHash.of(words), cloudHash = WordHash.of(cloud.words)
                if words.isEmpty || localHash == cloudHash || localHash == syncHash {
                    adopt(cloud)
                } else {
                    status = "choose which words to keep"
                    conflict = cloud
                }
            } else {
                cloudChunks = cloud?.chunks ?? 0
                await pushCloud()   // first sign-in: this device seeds the account
            }
        } catch {
            status = "couldn't reach your account — working on this device"
        }
        recount()
        flushLog()
    }

    private func adopt(_ cloud: CloudSnapshot) {
        let cloudHasLanguages = cloud.settings.learning != nil
        words = cloud.words
        settings.merge(cloud.settings)
        syncHash = WordHash.of(words)
        persistLocal()
        recount()
        status = "saved to account ✓"
        // A language picked on this device before signing in travels up to the account.
        if !cloudHasLanguages && hasLanguages { scheduleSave() }
    }

    enum ConflictChoice { case useAccount, mergeBoth, keepDevice }

    func resolveConflict(_ choice: ConflictChoice) {
        guard let cloud = conflict else { return }
        switch choice {
        case .useAccount:
            words = cloud.words
            settings.merge(cloud.settings)
        case .mergeBoth:
            let have = keys
            for w in cloud.words where !have.contains(w.key) { words.append(w) }
        case .keepDevice:
            break
        }
        conflict = nil
        recount()
        persistLocal()
        Task { await pushCloud() }
    }

    func signIn(email: String, password: String) async throws {
        try await CloudService.shared.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        try await CloudService.shared.signUp(email: email, password: password)
    }

    func resetPassword(email: String) async throws {
        try await CloudService.shared.resetPassword(email: email)
    }

    func signOut() {
        try? CloudService.shared.signOut()
    }

    // MARK: Review scheduling

    func newCapLeft() -> Int {
        let cap = settings.newPerDay
        guard settings.introDay == Stats.key(for: Date()) else { return cap }
        return max(0, cap - settings.introCount)
    }

    private func bumpIntro() {
        let day = Stats.key(for: Date())
        if settings.introDay != day {
            settings.introDay = day
            settings.introCount = 0
        }
        settings.introCount += 1
    }

    func dueCounts() -> (due: Int, fresh: Int) {
        let now = Date().timeIntervalSince1970 * 1000
        var due = 0, fresh = 0
        for w in words {
            if let c = w.c, !c.isNew { if c.d <= now { due += 1 } } else { fresh += 1 }
        }
        return (due, min(fresh, newCapLeft()))
    }

    func recount() {
        let c = dueCounts()
        dueTotal = c.due + c.fresh
    }

    /// The deck is a word list; a stale deck name falls back to everything.
    func deckWords() -> [Word] {
        guard let d = settings.deck else { return words }
        let sub = words.filter { $0.group == d }
        return sub.isEmpty ? words : sub
    }

    func buildQueue() -> [String] {
        let now = Date().timeIntervalSince1970 * 1000
        var due: [Word] = [], fresh: [Word] = []
        for w in deckWords() {
            if let c = w.c, !c.isNew { if c.d <= now { due.append(w) } } else { fresh.append(w) }
        }
        due.sort { ($0.c?.d ?? 0) < ($1.c?.d ?? 0) }
        return (due + fresh.prefix(newCapLeft())).map(\.key)
    }

    /// Next scheduled review across the whole file, for the empty state.
    func nextDueText() -> String {
        let now = Date().timeIntervalSince1970 * 1000
        var next: Double?
        for w in words {
            if let c = w.c, !c.isNew, c.d > now { next = min(next ?? c.d, c.d) }
        }
        let capReached = words.contains { $0.c == nil || $0.c!.isNew } && newCapLeft() == 0
        var t = ""
        if let next {
            let d = next - now
            let when = d < 3_600_000 ? "in \(max(1, Int((d / 60_000).rounded()))) min"
                : d < 86_400_000 ? "in \(Int((d / 3_600_000).rounded())) h"
                : "in \(Int((d / 86_400_000).rounded())) d"
            t = "Next review \(when)."
        }
        if capReached { t += (t.isEmpty ? "" : " ") + "New cards resume tomorrow — the daily cap is done." }
        return t.isEmpty ? "Search the dictionary and add words to keep the queue alive." : t
    }

    /// Grades a card and returns its new state (nil if the word vanished).
    @discardableResult
    func grade(key: String, rating: Rating) -> Card? {
        guard let i = words.firstIndex(where: { $0.key == key }) else { return nil }
        let now = Date()
        let wasNew = words[i].c?.isNew ?? true
        guard let res = try? FSRSScheduler.grade(words[i], rating: rating, now: now) else { return nil }
        words[i].c = FSRSScheduler.data(from: res.card)
        if wasNew { bumpIntro() }
        stats.bump(again: rating == .again, at: now)
        pendingLog.append(LogEntry(w: key, r: rating.rawValue, at: now.timeIntervalSince1970 * 1000,
                                   el: res.log.elapsedDays, sc: res.log.scheduledDays,
                                   st: res.log.state?.rawValue ?? 0))
        changed()
        scheduleLogFlush()
        return res.card
    }

    // MARK: Review log (append-only, offline-safe)

    private func scheduleLogFlush() {
        logTask?.cancel()
        logTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.flushLog()
        }
    }

    func flushLog() {
        guard let a = account, !pendingLog.isEmpty else { return }
        let taken = pendingLog
        pendingLog = []
        Task {
            var byDay: [String: [LogEntry]] = [:]
            for e in taken {
                byDay[Stats.key(for: Date(timeIntervalSince1970: e.at / 1000)), default: []].append(e)
            }
            do {
                for (day, entries) in byDay {
                    try await CloudService.shared.appendLog(uid: a.uid, day: day, entries: entries)
                }
                persistLocal()
            } catch {
                pendingLog = taken + pendingLog
                persistLocal()
            }
        }
    }

    // MARK: Word sets

    private static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")   // no 0/O/1/I/l

    static func generateCode() -> String {
        String((0..<7).map { _ in codeAlphabet.randomElement()! })
    }

    func createSet(name: String, desc: String, keys picked: Set<String>) async throws -> String {
        guard let a = account else { throw CloudError.signedOut }
        // Snapshot the word data only — no groups, timestamps, or review state travel.
        let snapshot = words.filter { picked.contains($0.key) }
            .map { Word(ru: $0.ru, ac: $0.ac, pr: $0.pr, en: $0.en, pos: $0.pos, g: "", x: $0.x) }
        var code = AppStore.generateCode()
        do {
            try await CloudService.shared.createSet(uid: a.uid, code: code, name: name, desc: desc, words: snapshot)
        } catch {
            code = AppStore.generateCode()
            try await CloudService.shared.createSet(uid: a.uid, code: code, name: name, desc: desc, words: snapshot)
        }
        return code
    }

    func listSets() async throws -> [SetInfo] {
        guard let a = account else { return [] }
        var sets = try await CloudService.shared.listSets(uid: a.uid)
        for i in sets.indices {
            sets[i].imports = (try? await CloudService.shared.countRedemptions(code: sets[i].code)) ?? 0
        }
        return sets
    }

    struct SetPreview {
        let set: SetSnapshot
        let fresh: [Word]
        let duplicates: Int
    }

    func previewSet(code: String) async throws -> SetPreview? {
        guard let set = try await CloudService.shared.getSet(code: code) else { return nil }
        let have = keys
        let fresh = set.words.filter { !have.contains($0.key) }
        return SetPreview(set: set, fresh: fresh, duplicates: set.words.count - fresh.count)
    }

    /// Merges a set in: imports tagged with the set name, entering the review
    /// queue as new cards under the daily cap; then records the redemption.
    func redeem(_ preview: SetPreview) async {
        let now = Date().timeIntervalSince1970 * 1000
        for w in preview.fresh {
            let pr = w.pr.isEmpty && Translit.containsCyrillic(w.ru)
                ? Translit.pronunciation(w.ac.isEmpty ? w.ru : w.ac) : w.pr
            words.append(Word(ru: w.ru, ac: w.ac, pr: pr, en: w.en, pos: w.pos,
                              g: preview.set.name, x: w.x, t: now))
        }
        changed()
        if let a = account {
            try? await CloudService.shared.redeemSet(code: preview.set.code, uid: a.uid)
        }
    }
}

/// One review session: a queue of card keys, the current card, and tallies.
@MainActor
final class ReviewSession: ObservableObject {
    @Published var queue: [String] = []
    @Published var current: Word?
    @Published var revealed = false
    @Published var preview: [Rating: Card] = [:]
    @Published var done = 0
    @Published var again = 0
    @Published var started = false

    func start(_ store: AppStore) {
        queue = store.buildQueue()
        done = 0
        again = 0
        started = true
        next(store)
    }

    func next(_ store: AppStore) {
        revealed = false
        preview = [:]
        if !queue.isEmpty {
            let key = queue.removeFirst()
            current = store.word(for: key)
            if current == nil { next(store) }
        } else {
            current = nil
        }
    }

    func reveal(_ store: AppStore) {
        guard let w = current, !revealed else { return }
        revealed = true
        preview = FSRSScheduler.preview(w, now: Date())
        if store.settings.autoSay { Pronouncer.shared.speak(w.ru) }
    }

    func grade(_ rating: Rating, _ store: AppStore) {
        guard let w = current, revealed else { return }
        done += 1
        if rating == .again { again += 1 }
        // Short learning steps come back within the session, like Again in Anki.
        if let card = store.grade(key: w.key, rating: rating),
           card.due.timeIntervalSinceNow <= 20 * 60 {
            queue.append(w.key)
        }
        next(store)
    }
}
