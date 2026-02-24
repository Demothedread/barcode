import Foundation
import Speech
import AVFoundation

/// On-device speech recognition for wake word detection and real-time transcription.
/// Uses Apple's Speech framework — works offline for wake word, online for full transcription.
@MainActor
final class SpeechRecognitionService {
    private weak var appState: AppState?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    /// Request authorization for speech recognition
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    /// Start live transcription (displays interim results while recording)
    func startLiveTranscription(onResult: @escaping (String, Bool) -> Void) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[Speech] Recognizer not available")
            return
        }
        
        // Cancel any previous task
        stopTranscription()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // Use on-device recognition if available (faster, works offline)
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = false // Use server for accuracy on legal terms
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
        } catch {
            print("[Speech] Audio engine start error: \(error)")
            return
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                onResult(text, isFinal)
            }
            
            if let error = error {
                print("[Speech] Recognition error: \(error)")
                self.stopTranscription()
            }
        }
    }
    
    func stopTranscription() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }
}
