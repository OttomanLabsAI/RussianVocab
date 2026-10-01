import SwiftUI

@MainActor struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            WordsView()
                .tabItem { Label("Words", systemImage: "list.bullet.rectangle") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            ReviewView()
                .tabItem { Label("Review", systemImage: "rectangle.on.rectangle") }
                .badge(store.dueTotal > 0 ? store.dueTotal : 0)
            StatsView()
                .tabItem { Label("Progress", systemImage: "chart.bar") }
            MoreView()
                .tabItem { Label("Account", systemImage: "person") }
        }
        .fullScreenCover(isPresented: Binding(get: { !store.hasLanguages || store.editingLanguages }, set: { _ in })) {
            OnboardingView().environmentObject(store)
        }
        .alert("From your teacher", isPresented: Binding(get: { store.inboxNotice != nil }, set: { if !$0 { store.inboxNotice = nil } })) {
            Button("OK") { store.inboxNotice = nil }
        } message: {
            Text(store.inboxNotice ?? "")
        }
        .alert("Your account and this device both have words",
               isPresented: Binding(get: { store.conflict != nil }, set: { _ in })) {
            Button("Use account") { store.resolveConflict(.useAccount) }
            Button("Merge both") { store.resolveConflict(.mergeBoth) }
            Button("Keep this device") { store.resolveConflict(.keepDevice) }
        } message: {
            Text("Your account has \(store.conflict?.words.count ?? 0) words; this device has \(store.words.count). Which should we keep?")
        }
    }
}

/// Shared page header: sparkle kicker, Prata title, micro readout.
struct PageHeader: View {
    let kicker: String
    let title: String
    var meta: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Sparkle(size: 11)
                MicroLabel(text: kicker, size: 10)
            }
            Text(title).font(Fonts.display(28)).foregroundStyle(Color.ink)
            if !meta.isEmpty { MicroLabel(text: meta, size: 10) }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
    }
}

/// Account and sets live behind one tab so the main four stay uncluttered.
@MainActor struct MoreView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PageHeader(kicker: "Vocab Folio", title: "Account")
                    AccountView()
                    LanguagesBox()
                    NavigationLink { SetsView() } label: {
                        Box {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    MicroLabel(text: "Word sets", color: .ink)
                                    Text("Share a batch of words with a code, or redeem one.")
                                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.ink60)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    NavigationLink { TeachingView() } label: {
                        Box {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    MicroLabel(text: "Teaching", color: .ink)
                                    Text("Link to a teacher with a code — or be one, and add words to your students’ files.")
                                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.ink60)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Search → Add builds your file · sign in to sync across devices · Dictionary: OpenRussian (CC-BY-SA), frequency: OpenSubtitles · Recorded audio: Wiktionary contributors via Wikimedia Commons (CC BY-SA)")
                        .font(Fonts.serifItalic(13)).foregroundStyle(Color.ink60)
                        .padding(.horizontal, 4)
                }
                .padding(14)
            }
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

@MainActor struct AccountView: View {
    @EnvironmentObject var store: AppStore
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var message = ""
    @State private var busy = false

    var body: some View {
        Box(padding: 0) {
            BoxTitle(text: store.account == nil ? "Sign in" : "Signed in")
            VStack(alignment: .leading, spacing: 12) {
                if let a = store.account {
                    Text(a.email ?? "account").font(Fonts.serif(17))
                    MicroLabel(text: store.status)
                    Button("Sign out") { store.signOut() }.buttonStyle(InkButtonStyle())
                } else {
                    Text("Sign in with the same email and password you use on the website — your words, lists, and review history are already here.")
                        .font(Fonts.serifItalic(15)).foregroundStyle(Color.ink60)
                    Field(label: "Email") {
                        TextField("", text: $email)
                            .textFieldStyle(InkTextFieldStyle())
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                    }
                    Field(label: "Password") {
                        SecureField("", text: $password).textFieldStyle(InkTextFieldStyle())
                    }
                    if !message.isEmpty {
                        Text(message).font(Fonts.serifItalic(14)).foregroundStyle(Color.accent)
                    }
                    HStack(spacing: 8) {
                        Button(creating ? "Create account" : "Sign in") { submit() }
                            .buttonStyle(InkButtonStyle(filled: true))
                            .disabled(busy)
                        Button(creating ? "Have an account?" : "New here?") { creating.toggle(); message = "" }
                            .buttonStyle(InkButtonStyle())
                        Button("Forgot?") { reset() }.buttonStyle(InkButtonStyle(compact: true))
                    }
                    MicroLabel(text: store.status)
                }
            }
            .padding(14)
        }
    }

    private func submit() {
        busy = true
        message = ""
        Task {
            do {
                if creating { try await store.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password) }
                else { try await store.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
                password = ""
            } catch {
                message = CloudService.friendly(error)
            }
            busy = false
        }
    }

    private func reset() {
        let e = email.trimmingCharacters(in: .whitespaces)
        guard !e.isEmpty else { message = "Enter your email first."; return }
        Task {
            do { try await store.resetPassword(email: e); message = "Reset email sent ✓" }
            catch { message = CloudService.friendly(error) }
        }
    }
}
