import Foundation

/// On-device persistence: one JSON file in Application Support, mirroring
/// what the web app keeps in localStorage.
enum Persistence {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("VocabFolio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    static func load() -> LocalState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(LocalState.self, from: data)
    }

    static func save(_ state: LocalState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The same 270-word starter file a fresh browser gets.
    static func starterWords() -> [Word] {
        guard let url = Bundle.main.url(forResource: "starter", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let words = try? JSONDecoder().decode([Word].self, from: data) else { return [] }
        return words.filter(\.isValid)
    }
}
