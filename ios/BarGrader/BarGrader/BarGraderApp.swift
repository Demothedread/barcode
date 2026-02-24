import SwiftUI
import AVFoundation
import AppIntents

@main
struct BarGraderApp: App {
    @StateObject private var appState = AppState.shared
    
    init() {
        configureAudioSession()
        observeAudioInterruptions()
        // Register App Shortcuts with the Shortcuts app.
        // Voice activation ("Hey Siri, Hey Bartender") requires paid Apple Developer Program.
        // Without it, shortcuts still work when triggered manually from the Shortcuts app.
        BartenderShortcuts.updateAppShortcutParameters()
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
    
    // MARK: - Audio Session Configuration
    
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
    
    // MARK: - Audio Interruption Handling
    
    /// Recover automatically when a phone call, alarm, or other app steals the audio session.
    /// Without this, the mic silently dies and the user has to force-quit.
    private func observeAudioInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
            
            switch type {
            case .began:
                print("[Audio] Interruption began (phone call / alarm / other app)")
                // If we were recording, stop gracefully — the audio hardware is gone
                Task { @MainActor in
                    if AppState.shared.isRecording {
                        AppState.shared.stopRecording()
                        AppState.shared.statusText = "Recording paused — audio interrupted"
                    }
                }
                
            case .ended:
                print("[Audio] Interruption ended")
                // Check if we should resume
                let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
                
                if shouldResume {
                    // Re-activate the session
                    do {
                        try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                        print("[Audio] Session reactivated after interruption")
                    } catch {
                        print("[Audio] Reactivation error: \(error)")
                    }
                    
                    Task { @MainActor in
                        AppState.shared.statusText = "Ready"
                        // Refresh detected audio routes (USB-C mic may have changed)
                        AppState.shared.refreshAudioRoutes()
                    }
                }
                
            @unknown default:
                break
            }
        }
        
        // Also observe media services reset (extremely rare but fatal without handling)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("[Audio] ⚠️ Media services were reset — reconfiguring from scratch")
            self.configureAudioSession()
            Task { @MainActor in
                AppState.shared.refreshAudioRoutes()
                AppState.shared.statusText = "Audio reset — ready"
            }
        }
    }
}
