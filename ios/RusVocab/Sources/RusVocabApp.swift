import SwiftUI

@main
@MainActor struct RusVocabApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var dictionary = RuDictionary()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(dictionary)
                .tint(.ink)
                .onAppear {
                    store.start()
                    dictionary.load()
                    #if DEBUG
                    // Handy when checking the bundled font names resolve.
                    for family in ["Afacad Flux", "Newsreader", "Prata"] {
                        print("font:", family, UIFont.fontNames(forFamilyName: family))
                    }
                    #endif
                }
        }
        .onChange(of: phase) { _, p in
            if p == .background || p == .inactive { store.flushSave() }
        }
    }
}
