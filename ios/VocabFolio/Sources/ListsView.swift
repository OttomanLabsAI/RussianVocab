import SwiftUI

/// Manage the word lists: use one for new words, rename, delete (keeping or
/// dropping its words), start a new one. Lists double as review decks.
@MainActor struct ListsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var message = ""
    @State private var renaming: String?
    @State private var renameTo = ""
    @State private var deleting: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader(kicker: "Списки", title: "Lists",
                               meta: "\(store.allLists.count) lists · any list can be reviewed alone as a deck")
                    listsBox
                    newBox
                }
                .padding(14)
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .alert("Rename list", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameTo)
                Button("Rename") {
                    if let r = renaming { store.renameList(r, to: renameTo) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Delete “\(deleting ?? "")”?",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                let n = store.words.filter { $0.g == deleting }.count
                if n > 0 {
                    Button("Keep the words, drop the list") {
                        if let d = deleting { store.deleteList(d, keepWords: true) }
                        deleting = nil
                    }
                    Button("Delete the \(n) \(n == 1 ? "word" : "words") too", role: .destructive) {
                        if let d = deleting { store.deleteList(d, keepWords: false) }
                        deleting = nil
                    }
                } else {
                    Button("Delete list", role: .destructive) {
                        if let d = deleting { store.deleteList(d, keepWords: false) }
                        deleting = nil
                    }
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            }
        }
    }

    private var listsBox: some View {
        let names = store.allLists
        let ungrouped = store.words.filter { $0.g.isEmpty }.count
        return Box(padding: 0) {
            BoxTitle(text: "Your lists")
            ForEach(Array(names.enumerated()), id: \.element) { i, g in
                row(g)
                if i < names.count - 1 || ungrouped > 0 { DashedRule().padding(.horizontal, 12) }
            }
            if ungrouped > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ungrouped").font(Fonts.serif(17)).fontWeight(.semibold).foregroundStyle(Color.ink)
                        Text("\(ungrouped) \(ungrouped == 1 ? "word" : "words") — in no list")
                            .font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
    }

    private func row(_ g: String) -> some View {
        let n = store.words.filter { $0.g == g }.count
        let current = g == store.settings.group
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(g).font(Fonts.serif(17)).fontWeight(.semibold).foregroundStyle(Color.ink)
                Text("\(n) \(n == 1 ? "word" : "words")\(current ? " · new words go here" : "")")
                    .font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
            }
            Spacer(minLength: 4)
            if !current {
                Button("Use") { store.setGroup(g) }.buttonStyle(InkButtonStyle(compact: true))
            }
            Menu {
                Button("Rename…") { renameTo = g; renaming = g }
                Button("Delete…", role: .destructive) { deleting = g }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15))
                    .foregroundStyle(Color.ink).frame(width: 30, height: 30).contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var newBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "New list")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Week 4 — travel", text: $newName).textFieldStyle(InkTextFieldStyle())
                    Button("Create") { create() }.buttonStyle(InkButtonStyle(filled: true))
                }
                if !message.isEmpty {
                    Text(message).font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                }
            }
            .padding(14)
        }
    }

    private func create() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if store.allLists.contains(n) { message = "There is already a list called that."; return }
        store.createList(n)
        newName = ""
        message = "“\(n)” is where new words go now."
    }
}
