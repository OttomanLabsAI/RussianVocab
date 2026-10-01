import SwiftUI

/// The word file: part-of-speech tabs, list blocks, hide-and-peek study mode.
@MainActor struct WordsView: View {
    @EnvironmentObject var store: AppStore
    @State private var pos: String = "saved"
    @State private var showLists = false
    @State private var groupFilter: [String: String] = [:]     // pos → group or "" for all
    @State private var hideRu = false
    @State private var hideEn = false
    @State private var hidePr = false
    @State private var peeked: Set<String> = []                  // "key|col"
    @State private var armed: String?                            // key awaiting "Remove?"

    private var counts: [String: Int] {
        var c: [String: Int] = [:]
        for w in store.words { c[w.pos, default: 0] += 1 }
        return c
    }

    /// "saved" is the tab of everything the learner added; the rest are
    /// parts of speech, falling back to the first one with words.
    private var activePos: String {
        if pos == "saved" { return pos }
        let c = counts
        if c[pos] != nil { return pos }
        return PartOfSpeech.order.first { c[$0] != nil } ?? "saved"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader(kicker: "\(Languages.pairLabel(native: store.settings.native, learning: store.settings.learning)) · Card file + dictionary",
                               title: "Vocab Folio",
                               meta: "\(store.words.count) words in your file")
                    studyBar
                    if store.words.isEmpty {
                        Box {
                            Text("Your file is empty.").font(Fonts.display(20))
                            Text("Search the dictionary and press Add — words land in their part-of-speech tab.")
                                .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).padding(.top, 6)
                        }
                    } else {
                        posTabs
                        if activePos == "saved" { savedPanel } else { panel }
                    }
                }
                .padding(14)
            }
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLists) { ListsView().environmentObject(store) }
        }
    }

    private var studyBar: some View {
        Box(padding: 10) {
            HStack(spacing: 8) {
                MicroLabel(text: "Hide")
                Button("Russian") { hideRu.toggle(); if hideRu { hideEn = false }; peeked = [] }
                    .buttonStyle(InkButtonStyle(filled: hideRu, compact: true))
                Button("English") { hideEn.toggle(); if hideEn { hideRu = false }; peeked = [] }
                    .buttonStyle(InkButtonStyle(filled: hideEn, compact: true))
                Button("Pronunc.") { hidePr.toggle(); peeked = [] }.buttonStyle(InkButtonStyle(filled: hidePr, compact: true))
                Spacer(minLength: 0)
                Button("Lists") { showLists = true }.buttonStyle(InkButtonStyle(compact: true))
            }
        }
    }

    private var posTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    pos = "saved"
                } label: {
                    HStack(spacing: 8) {
                        Text("Saved")
                        Text("\(store.savedWords.count)").opacity(0.65)
                    }
                }
                .buttonStyle(InkButtonStyle(filled: activePos == "saved", compact: true))
                ForEach(PartOfSpeech.order.filter { counts[$0] != nil }, id: \.self) { p in
                    Button {
                        pos = p
                    } label: {
                        HStack(spacing: 8) {
                            Text(PartOfSpeech.english(p))
                            Text("\(counts[p] ?? 0)").opacity(0.65)
                        }
                    }
                    .buttonStyle(InkButtonStyle(filled: activePos == p, compact: true))
                }
            }
            .padding(2)
        }
    }

    private var panel: some View {
        let p = activePos
        let idx = store.words.filter { $0.pos == p }
        var groups: [String] = []
        for w in idx where !groups.contains(w.group) { groups.append(w.group) }
        let sel = groupFilter[p] ?? ""
        let shown = groups.filter { sel.isEmpty || $0 == sel }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PartOfSpeech.english(p)).font(Fonts.display(24)).foregroundStyle(Color.ink)
                Text("\(PartOfSpeech.russian(p)) · \(idx.count) words").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
            }
            if groups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("All") { groupFilter[p] = "" }.buttonStyle(InkButtonStyle(filled: sel.isEmpty, compact: true))
                        ForEach(groups, id: \.self) { g in
                            Button(g) { groupFilter[p] = g }.buttonStyle(InkButtonStyle(filled: sel == g, compact: true))
                        }
                    }
                    .padding(2)
                }
            }
            if hideRu || hideEn || hidePr {
                Text("Recall the hidden word, then tap it to peek.").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
            }
            ForEach(shown, id: \.self) { g in
                Box(padding: 0) {
                    if groups.count > 1 { BoxTitle(text: g) }
                    let rows = idx.filter { $0.group == g }
                    ForEach(Array(rows.enumerated()), id: \.element.key) { i, w in
                        row(w)
                        if i < rows.count - 1 { DashedRule().padding(.horizontal, 12) }
                    }
                }
            }
        }
    }

    /// Everything the learner (or a teacher) added, newest first; the starter
    /// file stays out. Each row names its list and who sent it.
    private var savedPanel: some View {
        let rows = store.savedWords
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved words").font(Fonts.display(24)).foregroundStyle(Color.ink)
                Text("Everything you added — \(rows.count) \(rows.count == 1 ? "word" : "words"), newest first · the starter file is left out")
                    .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
            }
            if hideRu || hideEn || hidePr {
                Text("Recall the hidden word, then tap it to peek.").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
            }
            if rows.isEmpty {
                Box {
                    Text("Nothing saved yet.").font(Fonts.display(20))
                    Text("Words you add from the dictionary, a set or a teacher collect here, newest first.")
                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).padding(.top, 6)
                }
            } else {
                Box(padding: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.key) { i, w in
                        row(w, withList: true)
                        if i < rows.count - 1 { DashedRule().padding(.horizontal, 12) }
                    }
                }
            }
        }
    }

    private func row(_ w: Word, withList: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    cell(w.display, key: w.key, col: "ru", hidden: hideRu)
                        .font(Fonts.serif(19)).fontWeight(.semibold)
                    SpeakerButton(text: w.ru, size: 14)
                }
                if !w.pr.isEmpty {
                    cell(w.pr, key: w.key, col: "pr", hidden: hidePr)
                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    cell(w.en, key: w.key, col: "en", hidden: hideEn).font(Fonts.serif(17))
                    if !w.extraText.isEmpty {
                        Text(w.extraText).font(Fonts.serifItalic(13)).foregroundStyle(Color.ink60)
                    }
                }
                if withList {
                    MicroLabel(text: w.group + (w.by.map { " · from " + $0 } ?? ""), color: .ink35, size: 9)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                if let added = w.addedAt {
                    MicroLabel(text: Self.when(added), color: .ink35, size: 9)
                }
                removeButton(w.key)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func cell(_ text: String, key: String, col: String, hidden: Bool) -> some View {
        let id = key + "|" + col
        let masked = hidden && !peeked.contains(id)
        return Text(text)
            .foregroundStyle(Color.ink)
            .blur(radius: masked ? 8 : 0)
            .opacity(masked ? 0.35 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                guard hidden else { return }
                if peeked.contains(id) { peeked.remove(id) } else { peeked.insert(id) }
            }
    }

    private func removeButton(_ key: String) -> some View {
        Group {
            if armed == key {
                Button("Remove?") { store.remove(key); armed = nil }
                    .buttonStyle(InkButtonStyle(filled: true, accent: true, compact: true))
            } else {
                Button {
                    armed = key
                    Task {
                        try? await Task.sleep(for: .seconds(2.6))
                        if armed == key { armed = nil }
                    }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.ink35).frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from your file")
            }
        }
    }

    /// "05:17 PM" today, "21 Jul" this year, "Jul 2025" before — like the web app.
    static func when(_ d: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(d) { f.dateFormat = "hh:mm a" }
        else if Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year) { f.dateFormat = "d MMM" }
        else { f.dateFormat = "d MMM yyyy" }
        return f.string(from: d)
    }
}
