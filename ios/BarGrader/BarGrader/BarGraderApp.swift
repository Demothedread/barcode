import SwiftUI
import AVFoundation

@main
struct BarGraderApp: App {
    @StateObject private var appState = AppState.shared
    
    init() {
        configureAudioSession()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    appState.connectIfNeeded()
                }
        }
    }
    
    /// Configure audio session for background operation + Bluetooth
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // playAndRecord: allows mic + speaker simultaneously
            // .allowBluetooth: routes to BT headset/mic
            // .defaultToSpeaker: uses speaker when no BT/USB-C
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[Audio] Session configured for background + Bluetooth + USB-C")
        } catch {
            print("[Audio] Session config error: \(error)")
        }
    }
}
