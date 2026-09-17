import Foundation

enum Config {
    /// The web app this iOS app shares an account with; share links point here.
    static let siteURL = URL(string: "https://russianvocab.cloudflare-passport599.workers.dev")!
    static func shareURL(for code: String) -> URL { siteURL.appendingPathComponent("s/\(code)") }
}
