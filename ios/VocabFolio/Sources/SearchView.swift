import SwiftUI

/// Dictionary search with one-tap Add, in the web app's ranking.
@MainActor struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var dictionary: RuDictionary
    @State private var query = ""
    @State private var results: [DictEntry] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var newListPrompt = false
    @State private var newListName = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader(kicker: "Поиск", title: "Search",
                               meta: dictionary.ready ? "Dictionary: \(dictionary.entries.count.formatted()) entries" : "Dictionary loading…")
                    Box {
                        VStack(alignment: .leading, spacing: 12) {
                            Field(label: "Search the dictionary") {
                                TextField("Russian (вода or voda) or English (water)…", text: $query)
                                    .textFieldStyle(InkTextFieldStyle())
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focused)
                                    .submitLabel(.search)
                                    .onSubmit { focused = false }
                            }
                            Field(label: "Add new words to") {
                                Menu {
                                    ForEach(listNames, id: \.self) { g in
                                        Button(g) { store.setGroup(g) }
                                    }
                                    Divider()
                                    Button("+ New list…") { newListName = ""; newListPrompt = true }
                                } label: {
                                    HStack {
                                        Text(store.settings.group).font(Fonts.serif(17)).foregroundStyle(Color.ink)
                                        Spacer()
                                        Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(Color.ink)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 11)
                                    .background(Color.paper)
                                    .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
                                }
                            }
                        }
                    }
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty && query.count >= 2 {
                        resultsBox
                    }
                }
                .padding(14)
            }
            .paperBackground()
            .keyboardDismissal()
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: query) { _, q in schedule(q) }
            .onChange(of: dictionary.ready) { _, _ in schedule(query) }
            .alert("Name the new list", isPresented: $newListPrompt) {
                TextField("Lesson 3", text: $newListName)
                Button("Create") { store.setGroup(newListName) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var listNames: [String] {
        var names = store.groups
        if !names.contains(store.settings.group) { names.insert(store.settings.group, at: 0) }
        return names
    }

    private func schedule(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, dictionary.ready else { results = []; return }
        let entries = dictionary.entries
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                RuDictionary.search(trimmed, in: entries)
            }.value
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }

    private var resultsBox: some View {
        Box(padding: 0) {
            BoxTitle(text: results.isEmpty
                     ? (searching ? "Searching…" : "No matches — try a shorter stem, or English")
                     : "Dictionary — tap Add · \(results.count)\(results.count == 60 ? "+" : "") matches")
            ForEach(Array(results.enumerated()), id: \.element.id) { i, e in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 2) {
                            Text(e.display).font(Fonts.serif(19)).fontWeight(.semibold).foregroundStyle(Color.ink)
                            SpeakerButton(text: e.bare, size: 14)
                        }
                        Text(e.pronunciation).font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(e.en).font(Fonts.serif(16)).foregroundStyle(Color.ink)
                            MicroLabel(text: "#\(e.rank)", color: .ink35, size: 9)
                        }
                        MicroLabel(text: PartOfSpeech.english(e.pos), color: .ink, size: 9)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
                    }
                    Spacer(minLength: 4)
                    if store.has(e.key) {
                        Text("In file ✓").font(Fonts.micro(10)).tracking(2).textCase(.uppercase)
                            .foregroundStyle(Color.ink35)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .overlay(Rectangle().stroke(Color.hair, lineWidth: 1))
                    } else {
                        Button("+ Add") { store.add(e) }.buttonStyle(InkButtonStyle(compact: true))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                if i < results.count - 1 { DashedRule().padding(.horizontal, 12) }
            }
        }
    }
}
