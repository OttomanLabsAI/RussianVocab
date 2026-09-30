import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

struct Account: Equatable {
    let uid: String
    let email: String?
}

/// What the account holds, in the same shape the web app reads and writes.
struct CloudSnapshot {
    var words: [Word]
    var settings: Settings
    var stats: Stats
    var chunks: Int
}

struct SetInfo: Identifiable {
    let code: String
    let name: String
    let count: Int
    let created: Date?
    var imports: Int = 0
    var id: String { code }
}

struct SetSnapshot {
    let code: String
    let name: String
    let desc: String
    let words: [Word]
}

/// Firebase Auth + Firestore, wire-compatible with the web app:
///   users/{uid}                    → { v, chunks, count, settings, stats, updated }
///   users/{uid}/w/{0..n}           → { words: [...] } (1,000 per chunk)
///   users/{uid}/log/{YYYYMMDD}     → { e: [...] } (append-only review log)
///   sets/{CODE}, sets/{CODE}/redemptions/{uid}
@MainActor
final class CloudService {
    static let shared = CloudService()
    private let chunk = 1000
    private var db: Firestore { Firestore.firestore() }

    // MARK: Setup

    /// True once Firebase is configured. False means the bundled configuration
    /// was unusable, and the app runs on this device alone: no sign-in, no sync.
    private(set) var isConfigured = false

    /// Configures Firebase from the bundled GoogleService-Info.plist — the one
    /// file that carries the app's client identifiers, so nothing is repeated
    /// here. `FirebaseApp.configure` raises an Objective-C exception on a
    /// malformed app id, which Swift cannot catch, so it would take the whole
    /// app down at launch: the options are checked first and a bad file skipped.
    func configure() {
        if FirebaseApp.app() != nil { isConfigured = true; return }
        guard let options = Self.loadOptions() else {
            print("Firebase: no usable GoogleService-Info.plist — running without accounts")
            return
        }
        FirebaseApp.configure(options: options)
        isConfigured = true
        // Explicit load/save model like the web app — no local Firestore cache.
        let settings = FirestoreSettings()
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
    }

    /// The plist's options when they pass the check FirebaseCore applies, else nil.
    static func loadOptions() -> FirebaseOptions? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else { return nil }
        guard isValidAppID(options.googleAppID) else {
            print("Firebase: GoogleService-Info.plist has an unusable GOOGLE_APP_ID \(options.googleAppID)")
            return nil
        }
        return options
    }

    /// Mirrors FirebaseCore's `validateAppIDFormat`: `1:<project number>:ios:<hex>`.
    /// An id from another platform (the website's `…:web:…`) fails, as it does there.
    static func isValidAppID(_ id: String) -> Bool {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "1", parts[2] == "ios",
              !parts[1].isEmpty, parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              !parts[3].isEmpty, parts[3].allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return false }
        return true
    }

    // MARK: Auth

    @discardableResult
    func listen(_ handler: @escaping (Account?) -> Void) -> AuthStateDidChangeListenerHandle {
        Auth.auth().addStateDidChangeListener { _, user in
            handler(user.map { Account(uid: $0.uid, email: $0.email) })
        }
    }

    func signIn(email: String, password: String) async throws {
        guard isConfigured else { throw CloudError.unconfigured }
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        guard isConfigured else { throw CloudError.unconfigured }
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func resetPassword(email: String) async throws {
        guard isConfigured else { throw CloudError.unconfigured }
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signOut() throws { if isConfigured { try Auth.auth().signOut() } }

    /// Same wording as the web app's `friendlyError`.
    static func friendly(_ error: Error) -> String {
        let ns = error as NSError
        let name = ns.userInfo["FIRAuthErrorUserInfoNameKey"] as? String ?? ""
        let table: [String: String] = [
            "ERROR_INVALID_EMAIL": "That email address doesn't look right.",
            "ERROR_EMAIL_ALREADY_IN_USE": "An account with that email already exists — try signing in.",
            "ERROR_WEAK_PASSWORD": "Password needs at least 6 characters.",
            "ERROR_MISSING_PASSWORD": "Enter a password.",
            "ERROR_INVALID_CREDENTIAL": "Wrong email or password.",
            "ERROR_WRONG_PASSWORD": "Wrong email or password.",
            "ERROR_USER_NOT_FOUND": "No account with that email — create one?",
            "ERROR_TOO_MANY_REQUESTS": "Too many attempts — wait a minute and try again.",
            "ERROR_NETWORK_REQUEST_FAILED": "Network problem — check your connection.",
        ]
        return table[name] ?? (ns.localizedDescription.isEmpty ? "Something went wrong." : ns.localizedDescription)
    }

    // MARK: Word file sync

    func loadCloud(uid: String) async throws -> CloudSnapshot? {
        let userRef = db.collection("users").document(uid)
        let head = try await userRef.getDocument(source: .server)
        guard head.exists, let data = head.data() else { return nil }
        let snaps = try await userRef.collection("w").getDocuments(source: .server)
        var parts: [(Int, [Any])] = []
        for doc in snaps.documents {
            parts.append((Int(doc.documentID) ?? 0, doc.data()["words"] as? [Any] ?? []))
        }
        parts.sort { $0.0 < $1.0 }
        let words = parts.flatMap { $0.1 }.compactMap { Codec.decode(Word.self, from: $0) }.filter(\.isValid)
        return CloudSnapshot(
            words: words,
            settings: Codec.decode(Settings.self, from: data["settings"]) ?? Settings(),
            stats: Codec.decode(Stats.self, from: data["stats"]) ?? Stats(),
            chunks: (data["chunks"] as? Int) ?? parts.count)
    }

    func saveCloud(uid: String, words: [Word], settings: Settings, prevChunks: Int, stats: Stats) async throws -> Int {
        let batch = db.batch()
        let userRef = db.collection("users").document(uid)
        let n = max(1, Int(ceil(Double(words.count) / Double(chunk))))
        batch.setData([
            "v": 1, "chunks": n, "count": words.count,
            "settings": Codec.encode(settings) ?? [String: Any](),
            "stats": Codec.encode(stats) ?? [String: Any](),
            "updated": FieldValue.serverTimestamp(),
        ], forDocument: userRef)
        for i in 0..<n {
            let lo = i * chunk, hi = min(words.count, (i + 1) * chunk)
            let slice = lo < hi ? Array(words[lo..<hi]) : []
            batch.setData(["words": Codec.encode(slice) ?? [Any]()], forDocument: userRef.collection("w").document(String(i)))
        }
        if prevChunks > n {
            for i in n..<prevChunks { batch.deleteDocument(userRef.collection("w").document(String(i))) }
        }
        try await batch.commit()
        return n
    }

    func appendLog(uid: String, day: String, entries: [LogEntry]) async throws {
        let encoded = (Codec.encode(entries) as? [Any]) ?? []
        try await db.collection("users").document(uid).collection("log").document(day).setData([
            "e": FieldValue.arrayUnion(encoded),
            "updated": FieldValue.serverTimestamp(),
        ], merge: true)
    }

    // MARK: Word sets

    func createSet(uid: String, code: String, name: String, desc: String, words: [Word]) async throws {
        try await db.collection("sets").document(code).setData([
            "owner": uid, "name": name, "desc": desc,
            "words": Codec.encode(words) ?? [Any](), "count": words.count,
            "created": FieldValue.serverTimestamp(),
        ])
    }

    func getSet(code: String) async throws -> SetSnapshot? {
        guard isConfigured else { throw CloudError.unconfigured }
        let snap = try await db.collection("sets").document(code).getDocument(source: .server)
        guard snap.exists, let d = snap.data() else { return nil }
        let words = (d["words"] as? [Any] ?? []).compactMap { Codec.decode(Word.self, from: $0) }.filter(\.isValid)
        return SetSnapshot(code: code, name: d["name"] as? String ?? "Set",
                           desc: d["desc"] as? String ?? "", words: words)
    }

    func listSets(uid: String) async throws -> [SetInfo] {
        let snaps = try await db.collection("sets").whereField("owner", isEqualTo: uid).getDocuments(source: .server)
        var out: [SetInfo] = []
        for s in snaps.documents {
            let d = s.data()
            out.append(SetInfo(code: s.documentID, name: d["name"] as? String ?? "Set",
                               count: d["count"] as? Int ?? 0,
                               created: (d["created"] as? Timestamp)?.dateValue()))
        }
        return out.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }

    func redeemSet(code: String, uid: String) async throws {
        try await db.collection("sets").document(code).collection("redemptions").document(uid).setData([
            "user": uid, "at": FieldValue.serverTimestamp(),
        ])
    }

    func countRedemptions(code: String) async throws -> Int {
        let agg = try await db.collection("sets").document(code).collection("redemptions").count.getAggregation(source: .server)
        return Int(truncating: agg.count)
    }
}

/// Codable ⇄ Firestore-friendly `Any` (plain JSON containers).
enum Codec {
    static func encode<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, from any: Any?) -> T? {
        guard let any, JSONSerialization.isValidJSONObject(any),
              let data = try? JSONSerialization.data(withJSONObject: any) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
