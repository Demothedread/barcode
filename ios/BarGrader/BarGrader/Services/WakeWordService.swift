import Foundation
import Speech
import AVFoundation

/// Always-on wake word detection using Apple's Speech framework.
/// Runs in continuous mode to detect the wake word (e.g., "hey bargrader")
/// even when the app is in the foreground idle state.
/// When the wake word is detected, it triggers recording.
@MainActor
final class WakeWordService {
    private weak var appState: AppState?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isListening = false
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    /// Start listening for the wake word
    func startListening() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[Wake] Speech recognizer not available")
            return
        }
        
        // Request authorization first
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                print("[Wake] Speech recognition not authorized")
                return
            }
            DispatchQueue.main.async {
                self?.startEngine()
            }
        }
    }
    
    private func startEngine() {
        stopListening()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // Prefer on-device for wake word (lower latency, works offline)
        if #available(iOS 13, *) {
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
            }
        }
        
        recognitionRequest = request
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            print("[Wake] Listening for wake word: \(appState?.wakeWord ?? "hey bargrader")")
        } catch {
            print("[Wake] Engine start error: \(error)")
            return
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                let wakeWord = (self.appState?.wakeWord ?? "hey bargrader").lowercased()
                
                if text.contains(wakeWord) {
                    print("[Wake] Wake word detected! Triggering recording.")
                    self.stopListening()
                    Task { @MainActor in
                        self.appState?.startRecording()
                    }
                    return
                }
            }
            
            if let error = error {
                print("[Wake] Recognition error: \(error.localizedDescription)")
                self.isListening = false
                // Restart after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if self.appState?.inputMode == .voice && !(self.appState?.isRecording ?? false) {
                        self.startEngine()
                    }
                }
            }
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
    
    /// Restart listening (called after recording completes)
    func restartIfNeeded() {
        guard appState?.inputMode == .voice, !(appState?.isRecording ?? false) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startListening()
        }
    }
}
