import SwiftUI

/// Shareable word sets: create one from your file, share the code or link,
/// redeem someone else's. Requires an account — the words travel between people.
@MainActor struct SetsView: View {
    @EnvironmentObject var store: AppStore
    @State private var code = ""
    @State private var preview: AppStore.SetPreview?
    @State private var previewMessage = ""
    @State private var name = ""
    @State private var desc = ""
    @State private var picked: Set<String> = []
    @State private var createMessage = ""
    @State private var createdCode: String?
    @State private var mySets: [SetInfo] = []
    @State private var loadingSets = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(kicker: "Наборы", title: "Word Sets",
                           meta: "Share a batch of words with a code")
                if store.account == nil {
                    Box {
                        Text("Sign in to create and redeem word sets — they need an account so the words can travel between people.")
                            .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                    }
                } else {
                    redeemBox
                    createBox
                    mySetsBox
                }
            }
            .padding(14)
        }
        .paperBackground()
        .keyboardDismissal()
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSets() }
    }

    // MARK: Redeem

    private var redeemBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "Redeem a code")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("e.g. K7MPQ2A", text: $code)
                        .textFieldStyle(InkTextFieldStyle())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Redeem") { lookup() }.buttonStyle(InkButtonStyle(filled: true))
                }
                if let p = preview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("“\(p.set.name)”\(p.set.desc.isEmpty ? "" : " — \(p.set.desc)")").font(Fonts.serif(17))
                        Text("\(p.fresh.count) new words\(p.duplicates > 0 ? " (\(p.duplicates) already in your file)" : "").")
                            .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                        HStack(spacing: 8) {
                            if !p.fresh.isEmpty {
                                Button("Add to my file") {
                                    Task {
                                        await store.redeem(p)
                                        previewMessage = "Added \(p.fresh.count) words from “\(p.set.name)” — they join the review queue as new cards."
                                        preview = nil
                                    }
                                }.buttonStyle(InkButtonStyle(filled: true))
                            }
                            Button("Cancel") { preview = nil }.buttonStyle(InkButtonStyle())
                        }
                    }
                    .padding(12)
                    .overlay(Rectangle().stroke(Color.hair, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
                if !previewMessage.isEmpty {
                    Text(previewMessage).font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                }
            }
            .padding(14)
        }
    }

    private func lookup() {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard !c.isEmpty else { return }
        previewMessage = ""
        Task {
            do {
                if let p = try await store.previewSet(code: c) { preview = p }
                else { previewMessage = "No set found for code \(c) — check it and try again." }
            } catch {
                previewMessage = CloudService.friendly(error)
            }
        }
    }

    // MARK: Create

    private var createBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "Create a set")
            VStack(alignment: .leading, spacing: 12) {
                Field(label: "Set name") { TextField("Week 3 — food words", text: $name).textFieldStyle(InkTextFieldStyle()) }
                Field(label: "Description (optional)") { TextField("", text: $desc).textFieldStyle(InkTextFieldStyle()) }
                Field(label: "Words · \(picked.count) selected") { picker }
                HStack(spacing: 10) {
                    Button("Create set") { create() }.buttonStyle(InkButtonStyle(filled: true))
                    if !createMessage.isEmpty {
                        Text(createMessage).font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                    }
                }
                if let c = createdCode {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            MicroLabel(text: "Code", size: 9)
                            Text(c).font(Fonts.micro(16)).tracking(4)
                        }
                        Text(Config.shareURL(for: c).absoluteString).font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                        HStack(spacing: 8) {
                            Button("Copy link") { UIPasteboard.general.string = Config.shareURL(for: c).absoluteString }
                                .buttonStyle(InkButtonStyle(compact: true))
                            ShareLink(item: Config.shareURL(for: c)) { Text("Share…") }.buttonStyle(InkButtonStyle(compact: true))
                        }
                    }
                    .padding(12)
                    .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
                }
            }
            .padding(14)
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.words.isEmpty {
                Text("Your file is empty — add words first.").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
            }
            ForEach(store.groups, id: \.self) { g in
                let inGroup = store.words.filter { $0.group == g }
                let allOn = inGroup.allSatisfy { picked.contains($0.key) }
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if allOn { for w in inGroup { picked.remove(w.key) } }
                        else { for w in inGroup { picked.insert(w.key) } }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: allOn ? "checkmark.square" : "square").foregroundStyle(Color.ink)
                            MicroLabel(text: g, color: .ink, size: 10)
                            MicroLabel(text: "\(inGroup.count)", size: 10)
                            Spacer()
                        }
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                    DashedRule()
                    ForEach(inGroup) { w in
                        Button {
                            if picked.contains(w.key) { picked.remove(w.key) } else { picked.insert(w.key) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: picked.contains(w.key) ? "checkmark.square" : "square").foregroundStyle(Color.ink)
                                Text(w.ru).font(Fonts.serif(16)).fontWeight(.semibold).foregroundStyle(Color.ink)
                                Text(w.en).font(Fonts.serif(15)).foregroundStyle(Color.ink60).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay(Rectangle().stroke(Color.hair, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            }
        }
    }

    private func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { createMessage = "Give the set a name first."; return }
        guard !picked.isEmpty else { createMessage = "Tick at least one word."; return }
        guard picked.count <= 500 else { createMessage = "Sets are capped at 500 words."; return }
        createMessage = "Creating…"
        Task {
            do {
                let c = try await store.createSet(name: n, desc: desc.trimmingCharacters(in: .whitespaces), keys: picked)
                createdCode = c
                createMessage = ""
                picked = []
                await loadSets()
            } catch {
                createMessage = "Couldn’t create the set — \(CloudService.friendly(error))"
            }
        }
    }

    // MARK: My sets

    private var mySetsBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "My sets")
            VStack(alignment: .leading, spacing: 0) {
                if loadingSets {
                    Text("Loading…").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).padding(14)
                } else if mySets.isEmpty {
                    Text("No sets yet — tick some words above and create one.").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).padding(14)
                }
                ForEach(Array(mySets.enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 10) {
                        Text(s.code).font(Fonts.micro(12)).tracking(3)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).font(Fonts.serif(16)).fontWeight(.semibold)
                            Text("\(s.count) words · \(s.imports) \(s.imports == 1 ? "import" : "imports")")
                                .font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                        }
                        Spacer()
                        Button("Copy link") { UIPasteboard.general.string = Config.shareURL(for: s.code).absoluteString }
                            .buttonStyle(InkButtonStyle(compact: true))
                    }
                    .padding(12)
                    if i < mySets.count - 1 { DashedRule().padding(.horizontal, 12) }
                }
            }
        }
    }

    private func loadSets() async {
        guard store.account != nil else { return }
        loadingSets = true
        mySets = (try? await store.listSets()) ?? []
        loadingSets = false
    }
}
