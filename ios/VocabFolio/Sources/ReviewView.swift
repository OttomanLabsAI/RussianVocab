import SwiftUI
import FSRS

/// Review mode: FSRS-scheduled cards, reveal on tap, four grades with the
/// interval each would set. Hardware keyboards get space and 1–4.
@MainActor struct ReviewView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var session = ReviewSession()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader(kicker: "Повторение", title: "Review",
                               meta: "\(store.dueTotal) due · Recall it, reveal, then grade yourself")
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
            .onAppear { if !session.started { session.start(store) } }
            .background(keyboardShortcuts)
        }
    }

    private var settingsBox: some View {
        Box(padding: 10) {
            VStack(alignment: .leading, spacing: 10) {
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
                    MicroLabel(text: "Auto-play audio on reveal")
                    Button(store.settings.autoSay ? "On" : "Off") { store.setAutoSay(!store.settings.autoSay) }
                        .buttonStyle(InkButtonStyle(filled: store.settings.autoSay, compact: true))
                }
            }
        }
    }

    private func card(_ w: Word) -> some View {
        Box(padding: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(w.display).font(Fonts.display(40)).foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                    if !session.revealed {
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
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(w.en).font(Fonts.serif(22)).foregroundStyle(Color.ink).multilineTextAlignment(.center)
                            if !w.extraText.isEmpty {
                                Text(w.extraText).font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                            }
                        }
                        if !w.pr.isEmpty {
                            Text(w.pr).font(Fonts.serifItalic(16)).foregroundStyle(Color.ink60)
                        }
                        SpeakerButton(text: w.ru, size: 18)
                        grades
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var grades: some View {
        let now = Date()
        return HStack(spacing: 8) {
            gradeButton("Again", .again, now, accent: true)
            gradeButton("Hard", .hard, now)
            gradeButton("Good", .good, now)
            gradeButton("Easy", .easy, now)
        }
        .padding(.top, 10)
    }

    private func gradeButton(_ title: String, _ r: Rating, _ now: Date, accent: Bool = false) -> some View {
        Button {
            session.grade(r, store)
        } label: {
            VStack(spacing: 5) {
                Text(title)
                Text(session.preview[r].map { FSRSScheduler.interval($0.due, now: now) } ?? "–").opacity(0.65)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(InkButtonStyle(accent: accent, compact: true))
    }

    private var summary: some View {
        Box {
            VStack(alignment: .center, spacing: 8) {
                if session.done > 0 {
                    MicroLabel(text: "Session complete", color: .ink)
                    Text("\(session.done) \(session.done == 1 ? "card" : "cards") reviewed").font(Fonts.display(24))
                    Text("\(session.again) marked Again (\(session.done > 0 ? Int((100.0 * Double(session.again) / Double(session.done)).rounded()) : 0)%). \(store.nextDueText())")
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

    /// Invisible buttons that carry the hardware-keyboard shortcuts.
    private var keyboardShortcuts: some View {
        Group {
            Button("") { session.reveal(store) }.keyboardShortcut(.space, modifiers: [])
            Button("") { session.grade(.again, store) }.keyboardShortcut("1", modifiers: [])
            Button("") { session.grade(.hard, store) }.keyboardShortcut("2", modifiers: [])
            Button("") { session.grade(.good, store) }.keyboardShortcut("3", modifiers: [])
            Button("") { session.grade(.easy, store) }.keyboardShortcut("4", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
