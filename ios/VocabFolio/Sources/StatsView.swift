import SwiftUI
import Charts

/// Anki-style progress: today, card counts, a GitHub-style review calendar,
/// future due, and all-time totals — all from the synced daily aggregates.
@MainActor struct StatsView: View {
    @EnvironmentObject var store: AppStore

    private struct Counts { var fresh = 0, learning = 0, young = 0, mature = 0 }

    private var counts: Counts {
        var c = Counts()
        for w in store.words {
            guard let cd = w.c, !cd.isNew else { c.fresh += 1; continue }
            if cd.state == 2 { if cd.sd >= 21 { c.mature += 1 } else { c.young += 1 } }
            else { c.learning += 1 }
        }
        return c
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader(kicker: "Прогресс", title: "Progress",
                               meta: store.account == nil ? "Reviews on this device" : "Every review on this account, across devices")
                    todayBox
                    countsBox
                    calendarBox
                    futureBox
                    allTimeBox
                }
                .padding(14)
            }
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var today: DayStat { store.stats.days[Stats.key(for: Date())] ?? DayStat() }

    private var todayBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "Today")
            VStack(alignment: .leading, spacing: 6) {
                if today.n > 0 {
                    Text("\(today.n) \(today.n == 1 ? "card" : "cards") studied").font(Fonts.display(22))
                    Text("\(today.a) marked Again (\(Int((100.0 * Double(today.a) / Double(today.n)).rounded()))%).")
                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                } else {
                    Text("No cards studied today.").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                }
            }
            .padding(14)
        }
    }

    private var countsBox: some View {
        let c = counts
        let total = max(1, store.words.count)
        let rows: [(String, Int, Double)] = [("New", c.fresh, 0.15), ("Learning", c.learning, 0.4),
                                             ("Young", c.young, 0.7), ("Mature", c.mature, 1.0)]
        return Box(padding: 0) {
            BoxTitle(text: "Card counts")
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(rows, id: \.0) { r in
                            if r.1 > 0 {
                                Rectangle().fill(Color.ink.opacity(r.2))
                                    .frame(width: max(2, geo.size.width * CGFloat(r.1) / CGFloat(total)))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 10)
                .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
                ForEach(rows, id: \.0) { r in
                    HStack {
                        Rectangle().fill(Color.ink.opacity(r.2)).frame(width: 10, height: 10)
                        Text(r.0).font(Fonts.serif(16))
                        Spacer()
                        MicroLabel(text: "\(r.1)", color: .ink, size: 12)
                        MicroLabel(text: "\(Int((100.0 * Double(r.1) / Double(total)).rounded()))%", size: 11).frame(width: 44, alignment: .trailing)
                    }
                    DashedRule()
                }
                HStack {
                    Text("Total").font(Fonts.serif(16)).fontWeight(.semibold)
                    Spacer()
                    MicroLabel(text: "\(store.words.count)", color: .ink, size: 12)
                    Color.clear.frame(width: 44)
                }
            }
            .padding(14)
        }
    }

    // MARK: Calendar heatmap (53 weeks, Sunday-first like GitHub)

    private var calendarBox: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) - 1          // 0 = Sunday
        let start = cal.date(byAdding: .day, value: -(weekday + 52 * 7), to: today)!
        let maxN = max(1, store.stats.days.values.map(\.n).max() ?? 1)
        let todayKey = Stats.key(for: today)
        return Box(padding: 0) {
            BoxTitle(text: "Calendar · last 12 months")
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 2) {
                        VStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { d in
                                MicroLabel(text: ["", "M", "", "W", "", "F", ""][d], size: 8).frame(width: 14, height: 11)
                            }
                        }
                        ForEach(0..<53, id: \.self) { w in
                            VStack(spacing: 2) {
                                ForEach(0..<7, id: \.self) { d in
                                    let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                                    if date > today {
                                        Color.clear.frame(width: 11, height: 11)
                                    } else {
                                        let key = Stats.key(for: date)
                                        let n = store.stats.days[key]?.n ?? 0
                                        cellView(n: n, maxN: maxN, isToday: key == todayKey)
                                    }
                                }
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        MicroLabel(text: "Less", size: 9)
                        ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { o in
                            if o == 0 { Rectangle().stroke(Color.hair, lineWidth: 1).frame(width: 11, height: 11) }
                            else { Rectangle().fill(Color.ink.opacity(o)).frame(width: 11, height: 11) }
                        }
                        MicroLabel(text: "More", size: 9)
                    }
                    .padding(.top, 4)
                }
                .padding(14)
            }
        }
    }

    private func cellView(n: Int, maxN: Int, isToday: Bool) -> some View {
        let level = n == 0 ? 0.0 : max(0.25, (ceil(4.0 * Double(n) / Double(maxN))) / 4.0)
        return ZStack {
            if n == 0 { Rectangle().stroke(Color.hair, lineWidth: 1) }
            else { Rectangle().fill(Color.ink.opacity(level)) }
            if isToday { Rectangle().stroke(Color.accent, lineWidth: 1.5) }
        }
        .frame(width: 11, height: 11)
    }

    // MARK: Future due

    private struct DueDay: Identifiable { let day: Int; let count: Int; var id: Int { day } }

    private var futureDue: (days: [DueDay], backlog: Int) {
        let now = Date().timeIntervalSince1970 * 1000
        let startMs = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000
        var counts = [Int](repeating: 0, count: 31)
        var backlog = 0
        for w in store.words {
            guard let c = w.c, !c.isNew else { continue }
            if c.d < now { backlog += 1; continue }
            let d = Int(floor((c.d - startMs) / 86_400_000))
            if d >= 0 && d <= 30 { counts[d] += 1 }
        }
        return (counts.enumerated().map { DueDay(day: $0.offset, count: $0.element) }, backlog)
    }

    private var futureBox: some View {
        let fd = futureDue
        let total = fd.days.reduce(0) { $0 + $1.count }
        return Box(padding: 0) {
            BoxTitle(text: "Future due · next 30 days")
            VStack(alignment: .leading, spacing: 10) {
                Chart(fd.days) { d in
                    BarMark(x: .value("Day", d.day), y: .value("Reviews", d.count))
                        .foregroundStyle(Color.ink)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 5)) { _ in
                        AxisGridLine().foregroundStyle(Color.hair)
                        AxisValueLabel().foregroundStyle(Color.ink60)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Color.hair)
                        AxisValueLabel().foregroundStyle(Color.ink60)
                    }
                }
                .frame(height: 150)
                Text("Total: \(total) reviews · Average: \(String(format: "%.1f", Double(total) / 31)) reviews/day · Due tomorrow: \(fd.days.count > 1 ? fd.days[1].count : 0)\(fd.backlog > 0 ? " · Backlog: \(fd.backlog) overdue" : "")")
                    .font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
            }
            .padding(14)
        }
    }

    // MARK: All time

    private var allTime: (reviews: Int, active: Int, streak: Int, longest: Int) {
        let days = store.stats.days
        let cal = Calendar.current
        var reviews = 0, active = 0, longest = 0, run = 0
        var prev: Date?
        for key in days.keys.sorted() {
            let n = days[key]?.n ?? 0
            reviews += n
            guard n > 0, let dt = Self.date(fromKey: key) else { continue }
            active += 1
            if let p = prev, cal.dateComponents([.day], from: p, to: dt).day == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run)
            prev = dt
        }
        var streak = 0
        var cur = cal.startOfDay(for: Date())
        if (days[Stats.key(for: cur)]?.n ?? 0) == 0 { cur = cal.date(byAdding: .day, value: -1, to: cur)! }
        while (days[Stats.key(for: cur)]?.n ?? 0) > 0 {
            streak += 1
            cur = cal.date(byAdding: .day, value: -1, to: cur)!
        }
        return (reviews, active, streak, longest)
    }

    private static func date(fromKey k: String) -> Date? {
        guard k.count == 8, let y = Int(k.prefix(4)), let m = Int(k.dropFirst(4).prefix(2)), let d = Int(k.suffix(2)) else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d))
    }

    private var allTimeBox: some View {
        let a = allTime
        let rows: [(String, String)] = [
            ("Reviews", "\(a.reviews)"),
            ("Active days", "\(a.active)"),
            ("Average per active day", "\(a.active > 0 ? Int((Double(a.reviews) / Double(a.active)).rounded()) : 0)"),
            ("Current streak", "\(a.streak) \(a.streak == 1 ? "day" : "days")"),
            ("Longest streak", "\(a.longest) \(a.longest == 1 ? "day" : "days")"),
        ]
        return Box(padding: 0) {
            BoxTitle(text: "All time")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack {
                        Text(r.0).font(Fonts.serif(16))
                        Spacer()
                        MicroLabel(text: r.1, color: .ink, size: 12)
                    }
                    if i < rows.count - 1 { DashedRule() }
                }
            }
            .padding(14)
        }
    }
}
