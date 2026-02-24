import Foundation
import AVFoundation

/// Manages TTS audio playback with queue, pause/resume, speed control.
/// Receives MP3 data chunks from the server and plays them sequentially.
/// Supports section pauses (silence) between IRAC sections.
@MainActor
final class TTSPlaybackService: NSObject, AVAudioPlayerDelegate {
    private weak var appState: AppState?
    private var audioQueue: [PlaybackItem] = []
    private var currentPlayer: AVAudioPlayer?
    private var isPlaying = false
    private var pauseTimer: Timer?
    
    /// Represents either audio data or a timed silence pause
    enum PlaybackItem {
        case audio(Data)
        case pause(TimeInterval)
    }
    
    init(appState: AppState) {
        self.appState = appState
        super.init()
    }
    
    /// Add audio data to the playback queue
    func enqueue(_ data: Data) {
        audioQueue.append(.audio(data))
        if !isPlaying {
            playNext()
        }
    }
    
    /// Add a silence pause to the playback queue (between IRAC sections)
    func enqueuePause(seconds: TimeInterval) {
        audioQueue.append(.pause(seconds))
        if !isPlaying {
            playNext()
        }
    }
    
    /// Play the next item in the queue
    private func playNext() {
        guard !audioQueue.isEmpty else {
            isPlaying = false
            Task { @MainActor in
                appState?.isSpeaking = false
            }
            return
        }
        
        isPlaying = true
        let item = audioQueue.removeFirst()
        
        switch item {
        case .audio(let data):
            do {
                currentPlayer = try AVAudioPlayer(data: data)
                currentPlayer?.delegate = self
                currentPlayer?.enableRate = true
                currentPlayer?.rate = Float(appState?.ttsSpeed ?? 0.55)
                currentPlayer?.volume = 1.0
                currentPlayer?.prepareToPlay()
                currentPlayer?.play()
            } catch {
                print("[TTS] Playback error: \(error)")
                playNext() // Skip broken chunk
            }
            
        case .pause(let seconds):
            // Insert a timed silence — just wait, then continue
            pauseTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                self?.playNext()
            }
        }
    }
    
    func pause() {
        currentPlayer?.pause()
    }
    
    func resume() {
        currentPlayer?.play()
    }
    
    func stop() {
        audioQueue.removeAll()
        currentPlayer?.stop()
        currentPlayer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        isPlaying = false
    }
    
    func updatePlaybackRate(_ rate: Double) {
        currentPlayer?.rate = Float(rate)
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playNext() }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[TTS] Decode error: \(String(describing: error))")
        Task { @MainActor in self.playNext() }
    }
}
