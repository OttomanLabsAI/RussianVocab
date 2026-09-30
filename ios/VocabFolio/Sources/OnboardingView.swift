import SwiftUI

/// First-run language choice: the learner's language, then the language they
/// are learning. Only supported pairs are listed. The choice lands in
/// settings, which sync to the account like everything else.
@MainActor struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @State private var step = 1
    @State private var native: String?
    @State private var learning: String?
    @State private var signingIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if signingIn {
                    PageHeader(kicker: "Vocab Folio", title: "Sign in")
                    AccountView()
                    Button("Back") { signingIn = false }.buttonStyle(InkButtonStyle())
                } else {
                    PageHeader(kicker: "Step \(step) of 2",
                               title: step == 1 ? "What’s your language?" : "What are you learning?")
                    Text(step == 1
                         ? "The language you already speak — translations and hints are shown in it."
                         : "Your word file, dictionary and reviews all follow this language.")
                        .font(Fonts.serifItalic(16)).foregroundStyle(Color.ink60)
                    VStack(spacing: 8) {
                        ForEach(options) { lang in option(lang) }
                    }
                    Text("More languages are on the way.")
                        .font(Fonts.serifItalic(14)).foregroundStyle(Color.ink60)
                    HStack(spacing: 8) {
                        if store.editingLanguages && store.hasLanguages {
                            Button("Cancel") { store.editingLanguages = false }.buttonStyle(InkButtonStyle())
                        } else if store.account == nil {
                            Button("I have an account") { signingIn = true }.buttonStyle(InkButtonStyle())
                        }
                        Spacer(minLength: 0)
                        if step == 2 {
                            Button("Back") { step = 1 }.buttonStyle(InkButtonStyle())
                        }
                        Button(step == 1 ? "Continue" : "Start") { advance() }
                            .buttonStyle(InkButtonStyle(filled: true))
                            .disabled(selection == nil)
                            .opacity(selection == nil ? 0.35 : 1)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .paperBackground()
        .interactiveDismissDisabled()
        .onAppear {
            native = store.settings.native
            learning = store.settings.learning
        }
        // Signing in may bring the account's languages; if it doesn't, pick here.
        .onChange(of: store.account) { _, a in if a != nil { signingIn = false } }
    }

    private var options: [Language] {
        step == 1 ? Languages.nativeOptions : Languages.learningOptions(for: native ?? "")
    }

    private var selection: String? { step == 1 ? native : learning }

    private func option(_ lang: Language) -> some View {
        let on = selection == lang.code
        return Button {
            if step == 1 {
                if native != lang.code { native = lang.code; learning = nil }
            } else {
                learning = lang.code
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(lang.name).font(Fonts.serif(20))
                if lang.selfName != lang.name {
                    Text(lang.selfName).font(Fonts.serifItalic(16)).opacity(0.7)
                }
                Spacer(minLength: 0)
                Text(lang.code.uppercased()).font(Fonts.micro(10)).tracking(2).opacity(0.65)
            }
            .foregroundStyle(on ? Color.paper : Color.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Color.ink : Color.paper)
            .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func advance() {
        if step == 1 {
            if native != nil { step = 2 }
            return
        }
        guard let n = native, let l = learning else { return }
        store.setLanguages(native: n, learning: l)
    }
}

/// Account-tab box showing the chosen pair, with a way back into the picker.
@MainActor struct LanguagesBox: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Box(padding: 0) {
            BoxTitle(text: "Languages")
            HStack {
                Text(Languages.pairLabel(native: store.settings.native, learning: store.settings.learning))
                    .font(Fonts.serif(17)).foregroundStyle(Color.ink)
                Spacer()
                Button("Change") { store.editingLanguages = true }
                    .buttonStyle(InkButtonStyle(compact: true))
            }
            .padding(14)
        }
    }
}
