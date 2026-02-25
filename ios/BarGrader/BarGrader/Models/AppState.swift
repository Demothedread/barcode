import Foundation
import SwiftUI
import Combine
import AVFoundation
import MediaPlayer
import WatchConnectivity

/// Central app state – ObservableObject so all views react to changes
@MainActor
final class AppState: NSObject, ObservableObject {
    static let shared = AppState()
    
    // MARK: - Connection
    @AppStorage("serverURL") var serverURL: String = "https://barcode-production-0db7.up.railway.app"
    @Published var isConnected = false
    
    // MARK: - Settings
    @AppStorage("ttsSpeed") var ttsSpeed: Double = 0.55  // ~80 WPM (TTS-1 baseline ~150 WPM)
    @AppStorage("ttsVoice") var ttsVoice: String = "nova"
    @AppStorage("silenceThreshold") var silenceThreshold: Double = 2.0
    @AppStorage("wakeWord") var wakeWord: String = "hey bargrader"
    @AppStorage("micSensitivity") var micSensitivity: String = "high"
    @AppStorage("inputMode") var inputMode: InputMode = .voice
    
    // MARK: - Input Method Settings
    @AppStorage("useWakeWord") var useWakeWord: Bool = true
    @AppStorage("useSiriShortcut") var useSiriShortcut: Bool = false
    @AppStorage("autoStartRecording") var autoStartRecording: Bool = false
    @AppStorage("immediateTTSPlayback") var immediateTTSPlayback: Bool = true
    @AppStorage("useSilentAudioSession") var useSilentAudioSession: Bool = false
    @AppStorage("useStopWord") var useStopWord: Bool = true
    
    // MARK: - Runtime State
    @Published var statusText: String = "Ready"
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcript: String = ""
    @Published var answerText: String = ""
    @Published var isAnswerComplete = false
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var showSettings = false
    @Published var typedText: String = ""
    @Published var currentMode: String = "essay"   // "essay", "outline", "mbe", "quickhits", or "mbequiz"
    @Published var awaitingEssayConfirm = false     // outline done, awaiting "yes"
    
    // MARK: - Services
    var webSocketService: WebSocketService!
    var audioRecorder: AudioRecorderService!
    var speechService: SpeechRecognitionService!
    var ttsService: TTSPlaybackService!
    var remoteCommandService: RemoteCommandService!
    var wakeWordService: WakeWordService!
    var stopWordService: StopWordService!
    var localLLM: LocalLLMService!
    
    /// True when online pipeline should be bypassed in favor of on-device model.
    @Published var isOfflineMode = false
    
    // MARK: - Peripheral Detection
    @Published var detectedInputName: String = "Built-in Mic"
    @Published var detectedInputType: AVAudioSession.Port = .builtInMic
    @Published var detectedOutputName: String = "Speaker"
    @Published var detectedOutputType: AVAudioSession.Port = .builtInSpeaker
    @Published var isLavMicDetected: Bool = false
    @Published var isHeadphonesDetected: Bool = false
    @Published var isClickerDetected: Bool = false
    @Published var isWatchAvailable: Bool = false
    
    private var wcSession: WCSession?
    
    private override init() {
        super.init()
        webSocketService = WebSocketService(appState: self)
        audioRecorder = AudioRecorderService(appState: self)
        speechService = SpeechRecognitionService(appState: self)
        ttsService = TTSPlaybackService(appState: self)
        remoteCommandService = RemoteCommandService(appState: self)
        wakeWordService = WakeWordService(appState: self)
        stopWordService = StopWordService(appState: self)
        localLLM = LocalLLMService.shared
        
        setupWatchConnectivity()
        setupAudioRouteMonitoring()
        refreshAudioRoutes()
        
        // Pre-load the on-device model in background so offline fallback is instant
        localLLM.preloadModel()
    }
    
    // MARK: - WatchConnectivity Setup
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        wcSession = WCSession.default
        wcSession?.delegate = self
        wcSession?.activate()
        print("[iPhone] WatchConnectivity activated")
    }
    
    // MARK: - Audio Route Monitoring
    
    private func setupAudioRouteMonitoring() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAudioRoutes()
            }
        }
    }
    
    /// Scan current audio routes and update peripheral detection state.
    func refreshAudioRoutes() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        
        // --- Input detection ---
        let inputs = route.inputs
        if let input = inputs.first {
            detectedInputName = input.portName
            detectedInputType = input.portType
            isLavMicDetected = [
                .usbAudio, .bluetoothHFP, .bluetoothLE, .headsetMic, .headphones
            ].contains(input.portType)
        } else {
            // Check available (not yet active) inputs
            let available = session.availableInputs ?? []
            let external = available.first(where: {
                [.usbAudio, .bluetoothHFP, .bluetoothLE, .headsetMic, .headphones]
                    .contains($0.portType)
            })
            if let ext = external {
                detectedInputName = ext.portName
                detectedInputType = ext.portType
                isLavMicDetected = true
            } else {
                detectedInputName = available.first?.portName ?? "No Mic"
                detectedInputType = available.first?.portType ?? .builtInMic
                isLavMicDetected = false
            }
        }
        
        // --- Output detection ---
        let outputs = route.outputs
        if let output = outputs.first {
            detectedOutputName = output.portName
            detectedOutputType = output.portType
            isHeadphonesDetected = [
                .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
                .usbAudio, .airPlay, .carAudio
            ].contains(output.portType)
        } else {
            detectedOutputName = "Speaker"
            detectedOutputType = .builtInSpeaker
            isHeadphonesDetected = false
        }
        
        // --- Clicker detection ---
        // BT clickers appear as bluetoothHFP or bluetoothA2DP in the route,
        // or as an external BT device that responds to media commands.
        // We detect any paired BT audio device as a potential clicker.
        let allPorts = inputs.map(\.portType) + outputs.map(\.portType)
        let btPorts: Set<AVAudioSession.Port> = [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE]
        isClickerDetected = allPorts.contains(where: { btPorts.contains($0) })
        
        print("[Routes] Input: \(detectedInputName) (\(detectedInputType.rawValue)) | Output: \(detectedOutputName) (\(detectedOutputType.rawValue)) | Lav:\(isLavMicDetected) HP:\(isHeadphonesDetected) BT:\(isClickerDetected)")
        
        // Fix USB-C mic stealing Bluetooth output:
        // When USB-C input is active but output fell back to speaker,
        // and .defaultToSpeaker is the culprit, reconfigure without it.
        // When USB-C is unplugged (back to built-in mic), restore .defaultToSpeaker
        // so TTS plays through the loud speaker instead of the earpiece.
        let useSilent = UserDefaults.standard.bool(forKey: "useSilentAudioSession")
        if !useSilent {
            do {
                if detectedInputType == .usbAudio && detectedOutputType == .builtInSpeaker {
                    try session.setCategory(
                        .playAndRecord,
                        mode: .default,
                        options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay, .mixWithOthers]
                    )
                    // Force-remove any speaker override so BT output is restored
                    try session.overrideOutputAudioPort(.none)
                    // Re-apply USB-C as preferred input after category change
                    if let usbInput = (session.availableInputs ?? []).first(where: { $0.portType == .usbAudio }) {
                        try session.setPreferredInput(usbInput)
                    }
                    print("[Routes] Reconfigured: dropped .defaultToSpeaker + overrideOutput(.none) to restore BT output with USB-C mic")
                } else if detectedInputType == .builtInMic {
                    // Restore .defaultToSpeaker for normal speaker output
                    try session.setCategory(
                        .playAndRecord,
                        mode: .default,
                        options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker, .mixWithOthers]
                    )
                    print("[Routes] Restored .defaultToSpeaker (no USB-C mic)")
                }
            } catch {
                print("[Routes] Audio session reconfigure error: \(error)")
            }
        }
    }
    
    /// Human-readable label for a port type.
    static func portLabel(_ port: AVAudioSession.Port) -> String {
        switch port {
        case .usbAudio:       return "USB-C"
        case .bluetoothHFP:   return "Bluetooth HFP"
        case .bluetoothA2DP:  return "Bluetooth A2DP"
        case .bluetoothLE:    return "Bluetooth LE"
        case .headsetMic:     return "Wired Headset"
        case .headphones:     return "Headphones"
        case .builtInMic:     return "Built-in Mic"
        case .builtInSpeaker: return "Built-in Speaker"
        case .airPlay:        return "AirPlay"
        case .carAudio:       return "CarPlay"
        default:              return port.rawValue
        }
    }
    
    // MARK: - Actions
    
    func connectIfNeeded() {
        webSocketService.connect()
        remoteCommandService.setup()
        if inputMode == .voice && useWakeWord {
            wakeWordService.startListening()
        }
    }
    
    func startRecording() {
        guard !isRecording, !isProcessing else { return }
        resetAnswer()
        isRecording = true
        statusText = "Listening... speak now"
        wakeWordService.stopListening()
        audioRecorder.startRecording()
        // Start listening for stop phrases ("stop bartender", "I'm done", etc.)
        if useStopWord {
            stopWordService.startListening()
        }
        syncToWatch()
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        statusText = "Processing audio..."
        stopWordService.stopListening()
        audioRecorder.stopRecording()
        syncToWatch()
        // Audio data is sent via callback in AudioRecorderService
    }
    
    func sendText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        resetAnswer()
        isProcessing = true
        transcript = cleaned
        typedText = ""
        
        // Online-first: send to server if connected, fall back to on-device
        if isConnected && !isOfflineMode {
            statusText = "Generating IRAC answer..."
            webSocketService.sendText(cleaned)
        } else {
            runLocalInference(question: cleaned)
        }
    }
    
    func sendAudioData(_ data: Data) {
        isProcessing = true
        
        if isConnected && !isOfflineMode {
            statusText = "Transcribing audio..."
            webSocketService.sendAudio(data)
        } else {
            // Offline: use on-device Speech Recognition, then local LLM
            statusText = "Transcribing locally..."
            speechService.startLiveTranscription { [weak self] text, isFinal in
                guard let self = self, isFinal else { return }
                Task { @MainActor in
                    self.transcript = text
                    self.runLocalInference(question: text)
                }
            }
        }
    }
    
    func repeatAnswer() {
        guard !answerText.isEmpty else { return }
        ttsService.stop()
        statusText = "Repeating answer..."
        
        if isConnected && !isOfflineMode {
            webSocketService.sendRepeat(answerText)
        } else {
            // Offline: use Apple's AVSpeechSynthesizer for TTS
            speakLocalTTS(answerText)
        }
        syncToWatch()
    }
    
    /// Repeat only the last N sentences of the answer (voice command: "repeat last 3 sentences")
    func repeatLastSentences(_ count: Int = 3) {
        guard !answerText.isEmpty else { return }
        
        // Split on sentence-ending punctuation, keep non-empty
        let sentences = answerText
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let lastN = Array(sentences.suffix(count))
        let excerpt = lastN.joined(separator: ". ") + "."
        
        ttsService.stop()
        statusText = "Repeating last \(lastN.count) sentence\(lastN.count == 1 ? "" : "s")..."
        
        if isConnected && !isOfflineMode {
            webSocketService.sendRepeat(excerpt)
        } else {
            speakLocalTTS(excerpt)
        }
        syncToWatch()
    }
    
    func togglePause() {
        if isPaused {
            ttsService.resume()
            isPaused = false
        } else {
            ttsService.pause()
            isPaused = true
        }
        syncToWatch()
    }
    
    func stopSpeaking() {
        ttsService.stop()
        isSpeaking = false
        isPaused = false
    }
    
    func adjustSpeed(_ delta: Double) {
        ttsSpeed = max(0.5, min(2.0, ttsSpeed + delta))
        ttsService.updatePlaybackRate(ttsSpeed)
        syncToWatch()
    }
    
    func resetAnswer() {
        answerText = ""
        transcript = ""
        isAnswerComplete = false
        isSpeaking = false
        isPaused = false
        isProcessing = false
        ttsService.stop()
    }
    
    /// Full session reset — clears everything and tells the server
    func resetSession() {
        resetAnswer()
        currentMode = "essay"
        awaitingEssayConfirm = false
        typedText = ""
        statusText = "Session cleared. Ready for a new question."
        webSocketService.sendReset()
    }

    /// Cycle answer mode: essay → outline → mbe → quickhits → mbequiz → essay
    /// Called from BT stop button when idle, or from UI
    func cycleMode() {
        switch currentMode {
        case "essay":     currentMode = "outline"
        case "outline":   currentMode = "mbe"
        case "mbe":       currentMode = "quickhits"
        case "quickhits": currentMode = "mbequiz"
        default:          currentMode = "essay"
        }
        let label = currentMode.uppercased()
        statusText = "\(label) mode active"
        // Notify server of mode change
        webSocketService.sendText(currentMode == "mbe" ? "exam mode" : currentMode == "outline" ? "outline only" : "next question")
        syncToWatch()
    }

    /// Enter MBE / exam mode directly (BT shortcut or voice trigger)
    func enterExamMode() {
        guard currentMode != "mbe" else { return }
        currentMode = "mbe"
        statusText = "MBE exam mode active"
        webSocketService.sendText("exam mode")
        syncToWatch()
    }
    
    /// Enter Quick Hits mode — ultra-concise 1-4 sentence rule statements
    func enterQuickHitsMode() {
        guard currentMode != "quickhits" else { return }
        currentMode = "quickhits"
        statusText = "Quick Hits mode — rapid rule review"
        webSocketService.sendText("quick hits")
        syncToWatch()
    }
    
    /// Enter MBE Quiz mode — AI generates MBE questions for the user
    func enterMBEQuizMode() {
        guard currentMode != "mbequiz" else { return }
        currentMode = "mbequiz"
        statusText = "MBE Quiz mode — quiz me!"
        webSocketService.sendText("mbe quiz")
        syncToWatch()
    }
    
    /// Confirm: generate full essay from the last outline
    func confirmEssayFromOutline() {
        guard awaitingEssayConfirm else { return }
        awaitingEssayConfirm = false
        resetAnswer()
        isProcessing = true
        statusText = "Writing full essay from outline..."
        webSocketService.sendText("yes")
    }
    
    // MARK: - Offline Inference (on-device llama.cpp fallback)
    
    /// Run a question through the on-device LLM when server is unreachable.
    func runLocalInference(question: String) {
        guard localLLM.isModelLoaded else {
            statusText = "⚠️ No local model. Connect to server or add bargrader-model.gguf"
            isProcessing = false
            return
        }
        
        statusText = "🔌 Offline — generating on-device..."
        isOfflineMode = true
        answerText = ""
        
        Task {
            do {
                for try await token in localLLM.stream(question: question, mode: currentMode) {
                    answerText += token
                }
                
                isProcessing = false
                isAnswerComplete = true
                statusText = "⚡ Offline answer complete (local model)"
                syncToWatch()
                
                // Speak the answer using Apple TTS unless suppressed by settings
                if immediateTTSPlayback && !useSilentAudioSession {
                    speakLocalTTS(answerText)
                }
                
                // Restart wake word listening after answer
                if useWakeWord && inputMode == .voice {
                    wakeWordService.restartIfNeeded()
                }
                
            } catch {
                isProcessing = false
                statusText = "Local model error: \(error.localizedDescription)"
                syncToWatch()
            }
        }
    }
    
    /// Speak text using Apple's built-in AVSpeechSynthesizer (offline TTS).
    /// Lower quality than OpenAI TTS but works without network.
    private func speakLocalTTS(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = Float(ttsSpeed * 0.4)  // Scale down — AVSpeech rate is 0..1
        utterance.pitchMultiplier = 1.0
        
        let synth = AVSpeechSynthesizer()
        isSpeaking = true
        synth.speak(utterance)
    }
    
    // MARK: - WS Message Handlers (called by WebSocketService)
    
    func handleStatus(_ text: String) {
        statusText = text
    }
    
    func handleTranscript(_ text: String) {
        transcript = text
        statusText = "Generating IRAC answer..."
    }
    
    func handleToken(_ text: String) {
        isProcessing = true
        answerText += text
    }
    
    func handleTTSAudio(_ base64: String) {
        // Respect silent audio session — suppress all TTS playback
        guard !useSilentAudioSession else { return }
        guard let data = Data(base64Encoded: base64) else { return }
        isSpeaking = true
        ttsService.enqueue(data)
    }
    
    func handleSectionPause(seconds: Double) {
        // Insert a silence pause between IRAC sections
        ttsService.enqueuePause(seconds: seconds)
    }
    
    func handleDone(_ fullText: String) {
        isProcessing = false
        isAnswerComplete = true
        if awaitingEssayConfirm {
            statusText = "Outline complete. Say 'yes' for full essay, or ask a new question."
        } else if currentMode == "mbe" || currentMode == "quickhits" {
            statusText = "Answer delivered. Ask another question or say 'next question'."
        } else if currentMode == "mbequiz" {
            statusText = "Your turn — answer A, B, C, or D, or ask for another topic."
        } else {
            statusText = "Answer complete. Would you like me to repeat?"
        }
        syncToWatch()
        
        // Restart wake-word listening so the user can say the next command hands-free
        if useWakeWord && inputMode == .voice {
            wakeWordService.restartIfNeeded()
        }
    }
    
    func handleModeChange(mode: String, text: String) {
        currentMode = mode
        statusText = text
        syncToWatch()
    }
    
    func handleOutlinePrompt(_ text: String) {
        awaitingEssayConfirm = true
        statusText = text
    }
    
    func handleResetAck(_ text: String) {
        resetAnswer()
        currentMode = "essay"
        awaitingEssayConfirm = false
        typedText = ""
        statusText = text
    }
    
    func handleError(_ text: String) {
        isProcessing = false
        statusText = "Error: \(text)"
        syncToWatch()
    }
    
    // MARK: - Watch Sync
    
    /// Broadcast state to watch whenever something important changes
    func syncToWatch() {
        guard let session = wcSession, session.isReachable else { return }
        
        let message: [String: Any] = [
            "type": "status",
            "text": statusText,
            "recording": isRecording,
            "processing": isProcessing,
            "speaking": isSpeaking,
            "paused": isPaused,
            "mode": currentMode,
            "preview": answerPreview
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("[Watch Sync] Error: \(error.localizedDescription)")
        }
    }
    
    private var answerPreview: String {
        guard !answerText.isEmpty else { return "" }
        let lines = answerText.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: true)
        let preview = lines.prefix(2).joined(separator: "\n")
        return String(preview.prefix(100)) // Truncate for watch screen
    }
}

// MARK: - WCSessionDelegate

extension AppState: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("[iPhone] WC Session activated: \(activationState.rawValue)")
        Task { @MainActor in
            self.isWatchAvailable = (activationState == .activated) && session.isPaired && session.isWatchAppInstalled
        }
    }
    
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("[iPhone] WC Session inactive")
        Task { @MainActor in self.isWatchAvailable = false }
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[iPhone] WC Session deactivated")
        Task { @MainActor in self.isWatchAvailable = false }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in self.handleWatchMessage(message) }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any],
                 replyHandler: @escaping ([String : Any]) -> Void) {
        Task { @MainActor in self.handleWatchMessage(message) }
        replyHandler(["status": "received"])
    }
    
    private func handleWatchMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        
        Task { @MainActor in
            switch action {
            case "start_recording":
                self.startRecording()
            case "stop_recording":
                self.stopRecording()
            case "toggle_pause":
                self.togglePause()
            case "repeat_answer":
                self.repeatAnswer()
            case "increase_speed":
                self.adjustSpeed(0.1)
            case "reset_session":
                self.resetSession()
            case "cycle_mode":
                self.cycleMode()
            default:
                print("[iPhone] Unknown watch action: \(action)")
            }
            
            self.syncToWatch()
        }
    }
}

// MARK: - Input Mode

enum InputMode: String, CaseIterable {
    case voice = "voice"
    case keyboard = "keyboard"
}
