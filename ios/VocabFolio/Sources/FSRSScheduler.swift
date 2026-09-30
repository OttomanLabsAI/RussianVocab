import Foundation
import FSRS

/// The scheduler: the official Swift FSRS with the FSRS-6 default parameters —
/// the same 21 numbers, learning steps, and retention target the web app's
/// ts-fsrs uses, so a card graded on either platform lands on the same date.
enum FSRSScheduler {
    static let fsrs = FSRS(parameters: FSRSParameters(w: FSRSDefaults.defaultWv6))

    static func card(for w: Word) -> Card {
        guard let c = w.c else {
            return Card(due: w.addedAt ?? Date(), state: .new)
        }
        return Card(
            due: Date(timeIntervalSince1970: c.d / 1000),
            stability: c.sb, difficulty: c.df,
            elapsedDays: c.ed, scheduledDays: c.sd,
            learningSteps: Int(c.ls), reps: Int(c.r), lapses: Int(c.l),
            state: CardState(rawValue: c.state) ?? .new,
            lastReview: c.lr > 0 ? Date(timeIntervalSince1970: c.lr / 1000) : nil)
    }

    static func data(from card: Card) -> CardData {
        var c = CardData()
        c.d = card.due.timeIntervalSince1970 * 1000
        c.sb = card.stability
        c.df = card.difficulty
        c.ed = card.elapsedDays
        c.sd = card.scheduledDays
        c.r = Double(card.reps)
        c.l = Double(card.lapses)
        c.s = Double(card.state.rawValue)
        c.ls = Double(card.learningSteps)
        c.lr = card.lastReview.map { $0.timeIntervalSince1970 * 1000 } ?? 0
        return c
    }

    /// The four outcomes for a card right now, for the interval labels.
    static func preview(_ w: Word, now: Date) -> [Rating: Card] {
        guard let p = try? fsrs.`repeat`(card: card(for: w), now: now) else { return [:] }
        var out: [Rating: Card] = [:]
        for r in [Rating.again, .hard, .good, .easy] {
            if let item = p[r] { out[r] = item.card }
        }
        return out
    }

    static func grade(_ w: Word, rating: Rating, now: Date) throws -> RecordLogItem {
        try fsrs.next(card: card(for: w), now: now, grade: rating)
    }

    /// "1m", "6m", "10m", "8d", "3mo" — matches the web app's button labels.
    static func interval(_ due: Date, now: Date) -> String {
        let ms = due.timeIntervalSince(now) * 1000
        if ms < 3_600_000 { return "\(max(1, Int((ms / 60_000).rounded())))m" }
        if ms < 86_400_000 { return "\(Int((ms / 3_600_000).rounded()))h" }
        let d = Int((ms / 86_400_000).rounded())
        if d < 30 { return "\(d)d" }
        if d < 365 { return "\(Int((Double(d) / 30).rounded()))mo" }
        return String(format: "%.1fy", Double(d) / 365)
    }
}
