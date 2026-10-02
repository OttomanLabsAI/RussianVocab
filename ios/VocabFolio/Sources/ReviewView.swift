import SwiftUI
import FSRS

/// Review mode: FSRS-scheduled cards, reveal on tap, four grades with the
/// interval each would set. Hardware keyboards get space and 1–4.
@MainActor struct ReviewView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var dictionary: RuDictionary
    @StateObject private var session = ReviewSession()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader(kicker: "Повторение", title: "Review", meta: headerMeta)
                    settingsBox
                    if store.words.isEmpty {
                        Box {
                            Text("Your file is empty.").font(Fonts.display(20))
                            Text("Search the dictionary and add words — they come up for review here.")
                                .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).padding(.top, 6)
                        }
                    } else if let w = session.current {
                        card(w)
                        MicroLabel(text: "\(session.queue.count + 1) in session · \(session.done) done")
                    } else {
                        summary
                    }
                }
                .padding(14)
            }
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                session.dictionary = dictionary.entries
                if !session.started { session.start(store) }
            }
            .onChange(of: dictionary.ready) { _, _ in session.dictionary = dictionary.entries }
            .background(keyboardShortcuts)
        }
    }

    private var headerMeta: String {
        var parts = ["\(store.dueTotal) due"]
        if let d = store.settings.deck { parts.append(d) }
        if store.settings.reverse { parts.append("English → Russian") }
        if !store.sinceLabel.isEmpty { parts.append(store.sinceLabel) }
        parts.append(store.settings.quiz ? "pick the right answer" : "recall, reveal, then say if you got it")
        return parts.joined(separator: " · ")
    }

    private var settingsBox: some View {
        Box(padding: 10) {
            VStack(alignment: .leading, spacing: 10) {
                // The mode: a plain checkbox at the top.
                Button {
                    store.setQuiz(!store.settings.quiz)
                    session.revealed = false
                    session.pick = nil
                    session.deal(store)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: store.settings.quiz ? "checkmark.square" : "square")
                            .font(.system(size: 18)).foregroundStyle(Color.ink)
                        MicroLabel(text: "Multiple choice · pick from 5", color: .ink)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    store.setAutoSay(!store.settings.autoSay)
                    if store.settings.autoSay, session.revealed, let w = session.current { Pronouncer.shared.speak(w.ru) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: store.settings.autoSay ? "checkmark.square" : "square")
                            .font(.system(size: 18)).foregroundStyle(Color.ink)
                        MicroLabel(text: "Play the word on reveal", color: .ink)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: 10) {
                    MicroLabel(text: "Deck")
                    Menu {
                        Button("All lists") { store.setDeck(nil); session.start(store) }
                        ForEach(store.groups, id: \.self) { g in
                            Button(g) { store.setDeck(g); session.start(store) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(store.settings.deck ?? "All lists").font(Fonts.serif(16)).foregroundStyle(Color.ink)
                            Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(Color.ink)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    MicroLabel(text: "New cards per day")
                    Stepper(value: Binding(get: { store.settings.newPerDay }, set: { store.setNewPerDay($0) }), in: 0...500) {
                        Text("\(store.settings.newPerDay)").font(Fonts.serif(17)).foregroundStyle(Color.ink)
                    }
                    .fixedSize()
                }
                HStack(spacing: 10) {
                    MicroLabel(text: "Direction")
                    // One switch: English first, recall the Russian. Card state is shared.
                    Button(store.settings.reverse ? "EN → RU" : "RU → EN") {
                        store.setReverse(!store.settings.reverse)
                        session.revealed = false
                        session.pick = nil
                        session.deal(store)
                    }
                    .buttonStyle(InkButtonStyle(filled: store.settings.reverse, compact: true))
                }
                HStack(spacing: 10) {
                    MicroLabel(text: "Added")
                    Menu {
                        ForEach(Self.sinceOptions) { o in
                            Button(o.label) { store.setSince(o.days); session.start(store) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(Self.sinceOptions.first { $0.days == store.settings.since }?.label ?? "Any time")
                                .font(Fonts.serif(16)).foregroundStyle(Color.ink)
                            Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(Color.ink)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
                    }
                    Spacer()
                }
            }
        }
    }

    struct SinceOption: Identifiable {
        let days: Int
        let label: String
        var id: Int { days }
    }
    static let sinceOptions: [SinceOption] = [
        SinceOption(days: 0, label: "Any time"), SinceOption(days: 1, label: "Today"),
        SinceOption(days: 7, label: "Last 7 days"), SinceOption(days: 30, label: "Last 30 days"),
        SinceOption(days: 90, label: "Last 90 days"),
    ]

    private func card(_ w: Word) -> some View {
        let rev = store.settings.reverse
        let quiz = store.settings.quiz
        return Box(padding: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(rev ? w.en : w.display).font(rev ? Fonts.serif(30) : Fonts.display(40)).foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                    if rev, !w.extraText.isEmpty {
                        Text(w.extraText).font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                    }
                    if quiz {
                        choices
                        if session.pick == nil {
                            Text("pick the \(rev ? "Russian" : "English")").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink35).padding(.top, 10)
                        }
                    } else if !session.revealed {
                        Text("tap to reveal").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink35).padding(.top, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
                .onTapGesture { session.reveal(store) }

                if session.revealed {
                    DashedRule().padding(.horizontal, 20)
                    VStack(spacing: 8) {
                        if quiz, let p = session.pick {
                            if session.options[p].correct {
                                Text("Correct.").font(Fonts.serifItalic(18)).foregroundStyle(Color.ink60)
                            } else {
                                (Text("Not quite — it’s ").font(Fonts.serifItalic(18)).foregroundColor(.ink60)
                                 + Text(rev ? w.display : w.en).font(Fonts.serif(18)).fontWeight(.semibold).foregroundColor(.ink)
                                 + Text(".").font(Fonts.serifItalic(18)).foregroundColor(.ink60))
                                    .multilineTextAlignment(.center)
                            }
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(rev ? w.display : w.en).font(rev ? Fonts.display(28) : Fonts.serif(22))
                                    .foregroundStyle(Color.ink).multilineTextAlignment(.center)
                                if !rev, !w.extraText.isEmpty {
                                    Text(w.extraText).font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                                }
                            }
                        }
                        if !w.pr.isEmpty {
                            Text(w.pr).font(Fonts.serifItalic(16)).foregroundStyle(Color.ink60)
                        }
                        SpeakerButton(text: w.ru, size: 18)
                        if quiz {
                            Button("Next") { session.advance(store) }
                                .buttonStyle(InkButtonStyle(filled: true)).padding(.top, 10)
                        } else {
                            Text("Did you get it right?").font(Fonts.serifItalic(17)).foregroundStyle(Color.ink60).padding(.top, 10)
                            HStack(spacing: 10) {
                                Button("Incorrect") { session.grade(.again, store) }
                                    .buttonStyle(InkButtonStyle(accent: true)).frame(maxWidth: .infinity)
                                Button("Correct") { session.grade(.good, store) }
                                    .buttonStyle(InkButtonStyle(filled: true)).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    /// The five choices; after a pick the right one fills, a wrong pick turns accent.
    private var choices: some View {
        VStack(spacing: 8) {
            ForEach(Array(session.options.enumerated()), id: \.element.id) { i, o in
                let picked = session.pick
                let right = picked != nil && o.correct
                let wrong = picked == i && !o.correct
                Button {
                    session.choose(i, store)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(Fonts.micro(10)).tracking(2).opacity(0.55)
                        Text(o.text).font(Fonts.serif(17)).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(right ? Color.paper : (wrong ? Color.accent : Color.ink))
                    .background(right ? Color.ink : Color.paper)
                    .overlay(Rectangle().stroke(wrong ? Color.accent : Color.ink, lineWidth: 1))
                    .opacity(picked != nil && !right && !wrong ? 0.4 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(picked != nil)
            }
        }
        .padding(.top, 20)
    }

    private var summary: some View {
        Box {
            VStack(alignment: .center, spacing: 8) {
                if session.done > 0 {
                    MicroLabel(text: "Session complete", color: .ink)
                    Text("\(session.done) \(session.done == 1 ? "card" : "cards") reviewed").font(Fonts.display(24))
                    Text("\(session.again) marked Again (\(session.done > 0 ? Int((100.0 * Double(session.again) / Double(session.done)).rounded()) : 0)%). \(store.nextDueText())")
                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).multilineTextAlignment(.center)
                } else if store.settings.since > 0, store.deckWords().isEmpty {
                    Text("No words \(store.sinceLabel.lowercased()).").font(Fonts.display(22)).multilineTextAlignment(.center)
                    Text("Set Added back to Any time to review the whole file.")
                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).multilineTextAlignment(.center)
                } else {
                    Text("Nothing due right now.").font(Fonts.display(22))
                    Text(store.nextDueText()).font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).multilineTextAlignment(.center)
                }
                Button("Check again") { session.start(store) }.buttonStyle(InkButtonStyle(compact: true)).padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    /// Invisible buttons that carry the hardware-keyboard shortcuts: space
    /// reveals (or moves on in quiz mode); 1/2 are Incorrect/Correct, or 1–5
    /// pick a choice.
    private var keyboardShortcuts: some View {
        Group {
            Button("") { if store.settings.quiz { session.advance(store) } else { session.reveal(store) } }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { if store.settings.quiz { session.choose(0, store) } else { session.grade(.again, store) } }
                .keyboardShortcut("1", modifiers: [])
            Button("") { if store.settings.quiz { session.choose(1, store) } else { session.grade(.good, store) } }
                .keyboardShortcut("2", modifiers: [])
            Button("") { session.choose(2, store) }.keyboardShortcut("3", modifiers: [])
            Button("") { session.choose(3, store) }.keyboardShortcut("4", modifiers: [])
            Button("") { session.choose(4, store) }.keyboardShortcut("5", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
