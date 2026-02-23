import Foundation
import AVFoundation

/// Records audio from the microphone (including Bluetooth mics).
/// Detects silence to auto-stop, then sends the audio data to the backend.
final class AudioRecorderService: NSObject, AVAudioRecorderDelegate {
    private weak var appState: AppState?
    private var audioRecorder: AVAudioRecorder?
    private var silenceTimer: Timer?
    private var recordingURL: URL?
    private var levelCheckTimer: Timer?
    
    init(appState: AppState) {
        self.appState = appState
        super.init()
    }
    
    // MARK: - Recording
    
    func startRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "bargrader_recording_\(Date().timeIntervalSince1970).m4a"
        recordingURL = tempDir.appendingPathComponent(fileName)
        
        // Settings optimized for speech with high sensitivity
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            // High bit rate to capture soft speech
            AVEncoderBitRateKey: 128000,
        ]
        
        do {
            // Ensure audio session is active with correct route
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            
            // Check if external mic is available: Bluetooth, USB-C dongle, or wired headset
            let availableInputs = session.availableInputs ?? []

            // Priority order: USB-C dongle > Bluetooth HFP > Bluetooth LE > Wired headset > Built-in
            let preferredInput = availableInputs.first(where: {
                $0.portType == .usbAudio
            }) ?? availableInputs.first(where: {
                $0.portType == .bluetoothHFP
            }) ?? availableInputs.first(where: {
                $0.portType == .bluetoothLE
            }) ?? availableInputs.first(where: {
                $0.portType == .headsetMic
            }) ?? availableInputs.first(where: {
                $0.portType == .headphones  // some USB-C dongles appear as headphones
            })

            if let input = preferredInput {
                try session.setPreferredInput(input)
                print("[Mic] Using external mic: \(input.portName) (\(input.portType.rawValue))")
            } else {
                print("[Mic] Using built-in microphone")
            }
            
            // Boost input gain for whisper-level sensitivity
            if session.isInputGainSettable {
                let gainLevel: Float
                switch appState?.micSensitivity {
                case "high":   gainLevel = 1.0   // Maximum gain
                case "medium": gainLevel = 0.7
                default:       gainLevel = 0.4
                }
                try session.setInputGain(gainLevel)
                print("[Mic] Input gain set to \(gainLevel)")
            }
            
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            // Start silence detection
            startSilenceDetection()
            
            print("[Mic] Recording started")
        } catch {
            print("[Mic] Recording error: \(error)")
            Task { @MainActor in
                appState?.statusText = "Mic error: \(error.localizedDescription)"
                appState?.isRecording = false
            }
        }
    }
    
    func stopRecording() {
        levelCheckTimer?.invalidate()
        levelCheckTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        audioRecorder?.stop()
        
        // Read recorded data and send to server
        if let url = recordingURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                print("[Mic] Recording stopped, size: \(data.count) bytes")
                Task { @MainActor in
                    appState?.sendAudioData(data)
                }
                // Clean up
                try? FileManager.default.removeItem(at: url)
            } catch {
                print("[Mic] Error reading recording: \(error)")
            }
        }
        
        audioRecorder = nil
    }
    
    // MARK: - Silence Detection
    
    private func startSilenceDetection() {
        let threshold = appState?.silenceThreshold ?? 2.0
        let micSensitivity = appState?.micSensitivity ?? "high"
        
        // dB threshold: high sensitivity = detect very quiet audio
        let dbThreshold: Float
        switch micSensitivity {
        case "high":   dbThreshold = -55.0  // Very sensitive
        case "medium": dbThreshold = -45.0
        default:       dbThreshold = -35.0
        }
        
        var silenceStart: Date?
        
        levelCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            
            recorder.updateMeters()
            let avgPower = recorder.averagePower(forChannel: 0)
            
            if avgPower < dbThreshold {
                // Silence
                if silenceStart == nil {
                    silenceStart = Date()
                }
                let elapsed = Date().timeIntervalSince(silenceStart!)
                if elapsed >= threshold {
                    print("[Mic] Silence detected (\(elapsed)s), auto-stopping")
                    Task { @MainActor in
                        self.appState?.stopRecording()
                    }
                }
            } else {
                // Sound detected, reset
                silenceStart = nil
            }
        }
    }
    
    // MARK: - AVAudioRecorderDelegate
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("[Mic] Recording finished unsuccessfully")
        }
    }
}
