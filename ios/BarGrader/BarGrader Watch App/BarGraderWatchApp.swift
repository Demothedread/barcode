import SwiftUI
import WatchConnectivity

@main
struct BarGraderWatchApp: App {
    @StateObject private var watchState = WatchState.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchState)
                .preferredColorScheme(.dark)
        }
    }
}
