import SwiftUI
import SwiftData

@main
struct PandiaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Stage 4: persisted chat history — see ChatTurn.swift.
        .modelContainer(for: ChatTurn.self)
    }
}
