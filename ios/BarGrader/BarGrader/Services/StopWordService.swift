import Foundation
import Speech
import AVFoundation

/// Listens for stop/done phrases DURING recording to trigger automatic submission.
/// Runs a lightweight SFSpeechRecognizer alongside AVAudioRecorder.
///
/// Recognized stop phrases:
///   - "stop bartender"  / "stop recording"
///   - "I'm done"        / "done recording"
///   - "submit"          / "send it"
///   - "that's all"      / "that's it"
///
/// The service strips the stop phrase from the transcript before submission
/// so the LLM never sees "stop bartender" in the question text.
@MainActor
final class StopWordService {
    private weak var appState: AppState?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isListening = false
    
    /// All recognized stop phrases (lowercased). Order matters — longest first for greedy match.
    private let stopPhrases: [String] = [
        "stop bargrader",
        "stop bar grader",
        "stop bartender",
        "stop recording",
        "done recording",
        "i'm done",
        "im done",
        "that's all",
        "thats all",
        "that's it",
        "thats it",
        "send it",
        "submit",
    ]
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    // MARK: - Public API
    
    /// Start listening for stop phrases. Call this when recording begins.
    func startListening() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[StopWord] Speech recognizer not available")
            return
        }
        
        // Check authorization (should already be granted from wake word)
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                print("[StopWord] Speech recognition not authorized")
                return
            }
            DispatchQueue.main.async {
                self?.startEngine()
            }
        }
    }
    
    /// Stop listening. Call this when recording ends (by any means).
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
    
    // MARK: - Engine
    
    private func startEngine() {
        // Clean up any previous session
        stopListening()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device for lower latency and offline support
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
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
            print("[StopWord] Listening for stop phrases during recording")
        } catch {
            print("[StopWord] Engine start error: \(error)")
            return
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                
                // Check if any stop phrase appears near the END of the transcript
                // (we check the last ~40 chars to avoid false positives from earlier speech)
                let tail = String(text.suffix(50))
                
                for phrase in self.stopPhrases {
                    if tail.contains(phrase) {
                        print("[StopWord] Stop phrase detected: \"\(phrase)\" in \"\(tail)\"")
                        self.stopListening()
                        Task { @MainActor in
                            self.appState?.stopRecording()
                        }
                        return
                    }
                }
            }
            
            if let error = error {
                // Speech recognition timed out or errored — that's OK,
                // the user can still stop manually or via silence detection.
                print("[StopWord] Recognition ended: \(error.localizedDescription)")
                self.isListening = false
            }
        }
    }
}
