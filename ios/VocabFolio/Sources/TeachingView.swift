import SwiftUI

/// Teachers link to students with a code, see their files, and send words.
/// Students enter a teacher's code here too. See firestore.rules for the
/// consent model: a teacher can only reach a student who linked themself.
@MainActor struct TeachingView: View {
    @EnvironmentObject var store: AppStore
    @State private var code = ""
    @State private var createMessage = ""
    @State private var linkMessage = ""
    @State private var creating = false
    @State private var linking = false
    @State private var armedStudent: String?
    @State private var armedTeacher: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(kicker: "Учитель", title: "Teaching",
                           meta: "Link to students with a code · see their files · send words")
                if store.account == nil {
                    Box {
                        Text("Sign in to use teaching — a teacher and each student need their own account.")
                            .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                    }
                } else if !store.teachingLoaded {
                    Box { Text("Loading…").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60) }
                } else {
                    if !store.teachingError.isEmpty {
                        Box { Text(store.teachingError).font(Fonts.serifItalic(15)).foregroundStyle(Color.accent) }
                    }
                    codeBox
                    if store.teacherCode != nil { studentsBox }
                    teachersBox
                }
            }
            .padding(14)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { if !store.teachingLoaded { await store.loadTeaching() } }
        .refreshable { await store.loadTeaching() }
    }

    // MARK: Teacher code

    private var codeBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "Your teacher code")
            VStack(alignment: .leading, spacing: 10) {
                if let c = store.teacherCode {
                    Text(c).font(Fonts.micro(26)).tracking(8).foregroundStyle(Color.ink)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
                    Text("Students enter this under My teachers on their own Teaching page. Once linked, their file appears below and you can add or remove words for them.")
                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                    ShareLink(item: "My Vocab Folio teacher code is \(c) — enter it under Teaching → My teachers.") {
                        Text("Share code")
                    }
                    .buttonStyle(InkButtonStyle(compact: true))
                } else {
                    Text("Teachers get a code. Students enter it to link their file to you; from then on you can see their words and add or remove words for them — on their phone or on the website.")
                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                    HStack(spacing: 10) {
                        Button(creating ? "Creating…" : "Create my teacher code") { create() }
                            .buttonStyle(InkButtonStyle(filled: true)).disabled(creating)
                        if !createMessage.isEmpty {
                            Text(createMessage).font(Fonts.serifItalic(14)).foregroundStyle(Color.accent)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func create() {
        creating = true
        createMessage = ""
        Task {
            do { try await store.createTeacherCode() }
            catch { createMessage = "Couldn’t create a code — \(CloudService.friendly(error))" }
            creating = false
        }
    }

    // MARK: Students

    private var studentsBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "Students · \(store.students.count)")
            if store.students.isEmpty {
                Text("No students yet — give someone your code.")
                    .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).padding(14)
            }
            ForEach(Array(store.students.enumerated()), id: \.element.id) { i, st in
                HStack(spacing: 8) {
                    NavigationLink {
                        StudentView(student: st)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(st.email.isEmpty ? st.uid : st.email).font(Fonts.serif(17)).fontWeight(.semibold)
                                .foregroundStyle(Color.ink).lineLimit(1)
                            Text(studentMeta(st)).font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if armedStudent == st.uid {
                        Button("Remove?") { armedStudent = nil; Task { await store.removeStudent(st) } }
                            .buttonStyle(InkButtonStyle(filled: true, accent: true, compact: true))
                    } else {
                        Button("Remove") { arm(student: st.uid) }.buttonStyle(InkButtonStyle(compact: true))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                if i < store.students.count - 1 { DashedRule().padding(.horizontal, 12) }
            }
        }
    }

    private func studentMeta(_ st: StudentInfo) -> String {
        var parts = ["\(st.count) \(st.count == 1 ? "word" : "words")"]
        if let u = st.updated { parts.append("saved " + WordsView.when(u)) }
        if let d = st.lastReviewDay, let date = Stats.date(from: d) { parts.append("last review " + WordsView.when(date)) }
        return parts.joined(separator: " · ")
    }

    private func arm(student uid: String) {
        armedStudent = uid
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if armedStudent == uid { armedStudent = nil }
        }
    }

    // MARK: My teachers

    private var teachersBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "My teachers")
            VStack(alignment: .leading, spacing: 10) {
                Text("A linked teacher can see your file and add or remove words in it. Remove the link any time.")
                    .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                HStack(spacing: 8) {
                    TextField("Teacher code, e.g. K7MPQ2A", text: $code)
                        .textFieldStyle(InkTextFieldStyle())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button(linking ? "Linking…" : "Link") { link() }
                        .buttonStyle(InkButtonStyle(filled: true)).disabled(linking)
                }
                if !linkMessage.isEmpty {
                    Text(linkMessage).font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                }
            }
            .padding(14)
            ForEach(Array(store.teachers.enumerated()), id: \.element.id) { i, t in
                DashedRule().padding(.horizontal, 12)
                HStack(spacing: 8) {
                    Text(t.email.isEmpty ? t.uid : t.email).font(Fonts.serif(17)).fontWeight(.semibold)
                        .foregroundStyle(Color.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    if armedTeacher == t.uid {
                        Button("Remove?") { armedTeacher = nil; Task { await store.unlinkTeacher(t) } }
                            .buttonStyle(InkButtonStyle(filled: true, accent: true, compact: true))
                    } else {
                        Button("Remove") {
                            armedTeacher = t.uid
                            Task {
                                try? await Task.sleep(for: .seconds(2.6))
                                if armedTeacher == t.uid { armedTeacher = nil }
                            }
                        }
                        .buttonStyle(InkButtonStyle(compact: true))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
    }

    private func link() {
        let c = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard !c.isEmpty else { return }
        if store.teachers.contains(where: { $0.code == c }) { linkMessage = "Already linked."; return }
        linking = true
        linkMessage = ""
        Task {
            do {
                let t = try await store.linkTeacher(code: c)
                code = ""
                linkMessage = "Linked to \(t.email.isEmpty ? "your teacher" : t.email). They can now see your file and add words to it."
            } catch {
                linkMessage = CloudService.friendly(error)
            }
            linking = false
        }
    }
}

/// One student, as the teacher sees them: their file, a composer that sends
/// words into it, and whatever is still waiting for their app to open.
@MainActor struct StudentView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var dictionary: RuDictionary
    let student: StudentInfo
    @State private var file: CloudSnapshot?
    @State private var pending: [InboxItem] = []
    @State private var loadError = ""
    @State private var query = ""
    @State private var results: [DictEntry] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var basket: [DictEntry] = []
    @State private var listName = ""
    @State private var message = ""
    @State private var sending = false
    @State private var armed: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(kicker: "Student", title: student.email.isEmpty ? "Student" : student.email, meta: summary)
                composerBox
                if !pending.isEmpty { pendingBox }
                fileBox
            }
            .padding(14)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: query) { _, q in schedule(q) }
        .onAppear {
            if listName.isEmpty { listName = "From \(store.account?.email ?? "your teacher")" }
        }
    }

    private var words: [Word] { file?.words ?? [] }

    private var summary: String {
        guard let f = file else { return loadError.isEmpty ? "Loading…" : loadError }
        let now = Date().timeIntervalSince1970 * 1000
        let due = f.words.filter { w in
            if let c = w.c, !c.isNew { return c.d <= now }
            return false
        }.count
        return "\(f.words.count) \(f.words.count == 1 ? "word" : "words") · \(due) due"
    }

    private func load() async {
        do {
            file = try await store.loadStudentFile(student)
            pending = try await store.pending(for: student)
            loadError = ""
        } catch {
            loadError = CloudService.friendly(error)
        }
    }

    private func schedule(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, dictionary.ready else { results = []; return }
        let entries = dictionary.entries
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                RuDictionary.search(trimmed, in: entries)
            }.value
            guard !Task.isCancelled else { return }
            results = Array(found.prefix(10))
        }
    }

    // MARK: Composer

    private var composerBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "Add words for \(student.email.isEmpty ? "this student" : student.email)")
            VStack(alignment: .leading, spacing: 12) {
                Field(label: "Search the dictionary") {
                    TextField("Russian (вода or voda) or English (water)…", text: $query)
                        .textFieldStyle(InkTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if !results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, e in
                            resultRow(e)
                            if i < results.count - 1 { DashedRule() }
                        }
                    }
                    .overlay(Rectangle().stroke(Color.hair, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
                Field(label: "Chosen · \(basket.count)") {
                    if basket.isEmpty {
                        Text("Search above and press Add to collect words here.")
                            .font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(basket.enumerated()), id: \.element.id) { i, e in
                                HStack(spacing: 8) {
                                    Text(e.display).font(Fonts.serif(16)).fontWeight(.semibold).foregroundStyle(Color.ink)
                                    Text(e.en).font(Fonts.serif(15)).foregroundStyle(Color.ink60).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Button("Drop") { basket.removeAll { $0.id == e.id } }.buttonStyle(InkButtonStyle(compact: true))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                if i < basket.count - 1 { DashedRule() }
                            }
                        }
                        .overlay(Rectangle().stroke(Color.hair, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                }
                Field(label: "Into their list") {
                    TextField("", text: $listName).textFieldStyle(InkTextFieldStyle())
                }
                HStack(spacing: 10) {
                    Button(sending ? "Sending…" : "Send to student") { send() }
                        .buttonStyle(InkButtonStyle(filled: true))
                        .disabled(basket.isEmpty || sending)
                        .opacity(basket.isEmpty ? 0.35 : 1)
                    if !message.isEmpty {
                        Text(message).font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                    }
                }
            }
            .padding(14)
        }
    }

    private func resultRow(_ e: DictEntry) -> some View {
        let inFile = words.contains { $0.key == e.key }
        let sent = pending.contains { $0.add.contains { $0.key == e.key } }
        let chosen = basket.contains { $0.id == e.id }
        let label = inFile ? "In their file ✓" : sent ? "Sent ✓" : chosen ? "Chosen ✓" : ""
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.display).font(Fonts.serif(17)).fontWeight(.semibold).foregroundStyle(Color.ink)
                Text(e.en).font(Fonts.serif(15)).foregroundStyle(Color.ink60).lineLimit(1)
            }
            Spacer(minLength: 4)
            if label.isEmpty {
                Button("+ Add") { basket.append(e) }.buttonStyle(InkButtonStyle(compact: true))
            } else {
                Text(label).font(Fonts.micro(10)).tracking(2).textCase(.uppercase).foregroundStyle(Color.ink35)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func send() {
        let list = listName.trimmingCharacters(in: .whitespaces)
        let add = basket.map { Word(ru: $0.bare, ac: $0.ac, pr: $0.pronunciation, en: $0.en, pos: $0.pos, g: "", x: $0.x) }
        guard !add.isEmpty else { return }
        sending = true
        message = "Sending…"
        Task {
            do {
                try await store.send(to: student, add: add, remove: [],
                                     list: list.isEmpty ? "From \(store.account?.email ?? "your teacher")" : list)
                basket = []
                pending = (try? await store.pending(for: student)) ?? pending
                message = "Sent \(add.count) \(add.count == 1 ? "word" : "words") — it lands in their file the moment their app is open."
            } catch {
                message = "Couldn’t send — \(CloudService.friendly(error))"
            }
            sending = false
        }
    }

    // MARK: Pending

    private var pendingBox: some View {
        Box(padding: 0) {
            BoxTitle(text: "Waiting for their app to open")
            ForEach(Array(pending.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 8) {
                    Text(describe(p)).font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                    Spacer(minLength: 4)
                    Button("Withdraw") {
                        Task {
                            await store.withdraw(p, for: student)
                            pending = (try? await store.pending(for: student)) ?? []
                        }
                    }
                    .buttonStyle(InkButtonStyle(compact: true))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                if i < pending.count - 1 { DashedRule().padding(.horizontal, 12) }
            }
        }
    }

    private func describe(_ p: InboxItem) -> String {
        var parts: [String] = []
        if !p.add.isEmpty { parts.append("\(p.add.count) \(p.add.count == 1 ? "word" : "words") → “\(p.list)”") }
        if !p.remove.isEmpty { parts.append("remove \(p.remove.count) \(p.remove.count == 1 ? "word" : "words")") }
        if let at = p.at { parts.append("sent " + WordsView.when(at)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Their file

    private var removing: Set<String> { Set(pending.flatMap(\.remove)) }

    private var fileBox: some View {
        var groups: [String] = []
        for w in words where !groups.contains(w.group) { groups.append(w.group) }
        return Box(padding: 0) {
            BoxTitle(text: "Their file · \(words.count) \(words.count == 1 ? "word" : "words")")
            if file == nil {
                Text(loadError.isEmpty ? "Loading…" : loadError)
                    .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).padding(14)
            } else if words.isEmpty {
                Text("Their file is empty.").font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60).padding(14)
            }
            ForEach(groups, id: \.self) { g in
                let rows = words.filter { $0.group == g }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        MicroLabel(text: g, color: .ink, size: 10)
                        MicroLabel(text: "\(rows.count)", size: 10)
                        Spacer()
                    }
                    .padding(10)
                    DashedRule()
                    ForEach(rows) { w in
                        HStack(spacing: 8) {
                            Text(w.ru).font(Fonts.serif(16)).fontWeight(.semibold).foregroundStyle(Color.ink)
                            Text(w.en).font(Fonts.serif(15)).foregroundStyle(Color.ink60).lineLimit(1)
                            if let d = w.addedAt { MicroLabel(text: WordsView.when(d), color: .ink35, size: 9) }
                            Spacer(minLength: 4)
                            if removing.contains(w.key) {
                                MicroLabel(text: "removal sent", color: .ink35, size: 9)
                            } else if armed == w.key {
                                Button("Remove?") { armed = nil; sendRemoval(w.key) }
                                    .buttonStyle(InkButtonStyle(filled: true, accent: true, compact: true))
                            } else {
                                Button("Remove") {
                                    armed = w.key
                                    Task {
                                        try? await Task.sleep(for: .seconds(2.6))
                                        if armed == w.key { armed = nil }
                                    }
                                }
                                .buttonStyle(InkButtonStyle(compact: true))
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 6)
                .overlay(Rectangle().stroke(Color.hair, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .padding(10)
            }
        }
    }

    private func sendRemoval(_ key: String) {
        Task {
            do {
                try await store.send(to: student, add: [], remove: [key], list: "")
                pending = (try? await store.pending(for: student)) ?? pending
            } catch {
                message = "Couldn’t send — \(CloudService.friendly(error))"
            }
        }
    }
}
