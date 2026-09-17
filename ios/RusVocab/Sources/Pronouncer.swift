import AVFoundation

/// Pronunciation: a Wiktionary recording from Wikimedia Commons when one
/// exists (MP3 transcode — iOS can't decode the Ogg original), otherwise the
/// system's Russian voice. Any failure falls through silently to speech.
@MainActor
final class Pronouncer {
    static let shared = Pronouncer()

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var memo: [String: URL?] = [:]

    func speak(_ text: String) {
        let bare = Translit.bare(text).trimmingCharacters(in: .whitespaces)
        guard !bare.isEmpty else { return }
        activateSession()
        if bare.contains(" ") { tts(bare); return }
        Task {
            if let url = await commonsURL(for: bare.lowercased()), await play(url) { return }
            tts(bare)
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func tts(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synth.speak(u)
    }

    private func commonsURL(for word: String) async -> URL? {
        if let cached = memo[word] { return cached }
        var found: URL? = nil
        var comps = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        comps.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "titles", value: "File:Ru-\(word).ogg"),
            .init(name: "prop", value: "videoinfo"),
            .init(name: "viprop", value: "url|derivatives"),
            .init(name: "format", value: "json"),
        ]
        if let url = comps.url,
           let fetched = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: fetched.0) as? [String: Any],
           let query = json["query"] as? [String: Any],
           let pages = query["pages"] as? [String: Any] {
            for (_, page) in pages {
                guard let p = page as? [String: Any],
                      let vi = (p["videoinfo"] as? [[String: Any]])?.first,
                      let ders = vi["derivatives"] as? [[String: Any]],
                      let mp3 = ders.first(where: { ($0["type"] as? String)?.contains("audio/mpeg") == true }),
                      let src = mp3["src"] as? String, let u = URL(string: src) else { continue }
                found = u
            }
        }
        memo[word] = .some(found)
        return found
    }

    private func play(_ url: URL) async -> Bool {
        guard let fetched = try? await URLSession.shared.data(from: url),
              (fetched.1 as? HTTPURLResponse)?.statusCode == 200 else { return false }
        do {
            let p = try AVAudioPlayer(data: fetched.0)
            player = p
            p.prepareToPlay()
            return p.play()
        } catch {
            return false
        }
    }
}
