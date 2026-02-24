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
                    // Auto-start recording if the user opted in
                    if appState.autoStartRecording {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            appState.startRecording()
                        }
                    }
                }
        }
    }
    
    /// Configure audio session for background operation + Bluetooth
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        let useSilent = UserDefaults.standard.bool(forKey: "useSilentAudioSession")
        do {
            if useSilent {
                // Record-only: mic active, no speaker output
                try session.setCategory(
                    .record,
                    mode: .default,
                    options: [.allowBluetooth]
                )
            } else {
                // playAndRecord: allows mic + speaker simultaneously
                // .allowBluetooth: routes to BT headset/mic
                // .defaultToSpeaker: uses speaker when no BT/USB-C
                try session.setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker, .mixWithOthers]
                )
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[Audio] Session configured\(useSilent ? " (silent/record-only)" : " for background + Bluetooth + USB-C")")
        } catch {
            print("[Audio] Session config error: \(error)")
        }
    }
}
