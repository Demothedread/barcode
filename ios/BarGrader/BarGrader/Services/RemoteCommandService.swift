import Foundation
import MediaPlayer

/// Handles lock screen / Control Center media controls and Bluetooth HID button events.
/// This is the KEY service that lets the app respond from the lock screen:
///
/// - Bluetooth clicker "play" button → starts recording
/// - Bluetooth clicker "pause" button → stops recording / pauses TTS
/// - Volume buttons on headset → speed control
/// - Lock screen controls show current status
@MainActor
final class RemoteCommandService {
    private weak var appState: AppState?
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    /// Setup all remote command handlers
    func setup() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // ---- Play = Start Recording ----
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let state = self.appState else { return }
                if state.isRecording {
                    // Already recording, ignore
                } else if state.isSpeaking {
                    state.togglePause() // Resume if paused
                } else {
                    state.startRecording()
                }
            }
            return .success
        }
        
        // ---- Pause = Stop Recording / Pause TTS ----
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let state = self.appState else { return }
                if state.isRecording {
                    state.stopRecording()
                } else if state.isSpeaking {
                    state.togglePause()
                }
            }
            return .success
        }
        
        // ---- Toggle Play/Pause (single button clickers) ----
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let state = self.appState else { return }
                if state.isRecording {
                    state.stopRecording()
                } else if state.isSpeaking {
                    state.togglePause()
                } else {
                    state.startRecording()
                }
            }
            return .success
        }
        
        // ---- Stop = Stop everything / Toggle exam mode (when idle) ----
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let state = self?.appState else { return }
                if state.isRecording || state.isSpeaking || state.isProcessing {
                    // Active session — stop everything
                    state.stopSpeaking()
                    state.resetAnswer()
                } else {
                    // Idle — cycle mode (essay → outline → mbe → essay)
                    state.cycleMode()
                }
            }
            return .success
        }
        
        // ---- Next Track = Repeat Answer ----
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.appState?.repeatAnswer()
            }
            return .success
        }
        
        // ---- Previous Track = Increase speed ----
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.appState?.adjustSpeed(0.1)
            }
            return .success
        }
        
        // Set initial Now Playing info
        updateNowPlayingInfo(title: "Bartender", status: "Ready")
    }
    
    /// Update the lock screen / Control Center info display
    func updateNowPlayingInfo(title: String, status: String) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = status
        info[MPMediaItemPropertyAlbumTitle] = "CA Bar Exam Tutor"
        info[MPNowPlayingInfoPropertyPlaybackRate] = appState?.ttsSpeed ?? 1.0
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
