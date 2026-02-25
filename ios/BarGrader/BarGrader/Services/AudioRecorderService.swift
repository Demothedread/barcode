import Foundation
import AVFoundation

/// Records audio from the microphone (including Bluetooth mics).
/// Detects silence to auto-stop, then sends the audio data to the backend.
@MainActor
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
        let fileName = "bartender_recording_\(Date().timeIntervalSince1970).m4a"
        recordingURL = tempDir.appendingPathComponent(fileName)
        
        // Detect USB-C audio input for whisper-optimized capture
        let preSession = AVAudioSession.sharedInstance()
        let isUSBCInput = (preSession.availableInputs ?? []).contains(where: { $0.portType == .usbAudio })
        
        // RODE USB-C LAV MIC: Hypersensitive whisper capture mode
        // When USB-C mic detected: 16kHz sample rate, max quality, 192kbps for optimal whisper SNR
        let settings: [String: Any] = isUSBCInput ? [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
            AVEncoderBitRateKey: 192000,
        ] : [
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
            
            // RODE USB-C LAV MIC: Hypersensitive whisper capture mode
            if isUSBCInput {
                try session.setPreferredIOBufferDuration(0.005)  // 5ms for tighter capture
                print("[Mic] USB-C detected: 5ms IO buffer, 16kHz speech-optimized capture")
            }
            
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
                
                // When using USB-C mic, reconfigure audio session WITHOUT .defaultToSpeaker.
                // Without this, iOS treats USB-C as a wired route, drops Bluetooth output,
                // and .defaultToSpeaker sends audio to the built-in speaker instead.
                if input.portType == .usbAudio {
                    // RODE USB-C LAV MIC: .measurement disables AGC so whispers aren't
                    // normalized up with the noise floor. .allowBluetoothA2DP keeps
                    // Bluetooth output alive for TTS playback.
                    try session.setCategory(
                        .playAndRecord,
                        mode: .measurement,
                        options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay, .mixWithOthers]
                    )
                    // Force-clear any speaker override — lets iOS route output back to BT
                    try session.overrideOutputAudioPort(.none)
                    try session.setPreferredInput(input)  // re-apply after category change
                    print("[Mic] USB-C whisper mode: .measurement + overrideOutput(.none) → BT output preserved")
                }
            } else {
                print("[Mic] Using built-in microphone")
            }
            
            // Boost input gain for whisper-level sensitivity
            if session.isInputGainSettable {
                let gainLevel: Float
                if isUSBCInput {
                    // RODE USB-C LAV MIC: Maximum gain unconditionally for whisper capture
                    gainLevel = 1.0
                } else {
                    switch appState?.micSensitivity {
                    case "high":   gainLevel = 1.0   // Maximum gain
                    case "medium": gainLevel = 0.7
                    default:       gainLevel = 0.4
                    }
                }
                try session.setInputGain(gainLevel)
                print("[Mic] Input gain set to \(gainLevel) (USB-C: \(isUSBCInput))")
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
        
        // threshold == 0 means "Manual stop only" — no auto-silence detection
        guard threshold > 0 else {
            print("[Mic] Silence detection disabled (manual stop mode)")
            return
        }
        
        let micSensitivity = appState?.micSensitivity ?? "high"
        let isUSBC = appState?.detectedInputType == .usbAudio
        
        // dB threshold: high sensitivity = detect very quiet audio
        // RODE USB-C LAV MIC: Even more sensitive thresholds for whisper capture
        let dbThreshold: Float
        if isUSBC {
            switch micSensitivity {
            case "high":   dbThreshold = -65.0  // Hypersensitive for USB-C whisper
            case "medium": dbThreshold = -55.0
            default:       dbThreshold = -45.0
            }
        } else {
            switch micSensitivity {
            case "high":   dbThreshold = -55.0  // Very sensitive
            case "medium": dbThreshold = -45.0
            default:       dbThreshold = -35.0
            }
        }
        
        // Adaptive noise floor: measure ambient level over first 0.5s,
        // then treat anything within 6dB of that floor as background noise.
        // This eliminates constant AC / fan / traffic hum while still
        // catching whispers that rise above the floor.
        var silenceStart: Date?
        var noiseFloorSamples: [Float] = []
        var adaptiveFloor: Float? = nil
        let noiseCalibrationSamples = 5  // 5 × 0.1s = 0.5s calibration window
        let noiseMargin: Float = 6.0     // dB above floor to count as speech
        
        levelCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            
            recorder.updateMeters()
            let avgPower = recorder.averagePower(forChannel: 0)
            
            // --- Noise floor calibration (first 0.5s) ---
            if adaptiveFloor == nil {
                noiseFloorSamples.append(avgPower)
                if noiseFloorSamples.count >= noiseCalibrationSamples {
                    let measuredFloor = noiseFloorSamples.reduce(0, +) / Float(noiseFloorSamples.count)
                    // Use the HIGHER (less sensitive) of measured floor+margin or the
                    // configured dbThreshold, so we never accidentally silence-out speech.
                    adaptiveFloor = max(measuredFloor + noiseMargin, dbThreshold)
                    print("[Mic] Noise floor calibrated: \(measuredFloor) dB → adaptive threshold: \(adaptiveFloor!) dB (static: \(dbThreshold) dB)")
                }
                return  // Skip silence detection during calibration
            }
            
            let effectiveThreshold = adaptiveFloor!
            
            if avgPower < effectiveThreshold {
                // Silence (or constant background noise)
                if silenceStart == nil {
                    silenceStart = Date()
                }
                let elapsed = Date().timeIntervalSince(silenceStart!)
                if elapsed >= threshold {
                    print("[Mic] Silence detected (\(elapsed)s, floor: \(effectiveThreshold) dB), auto-stopping")
                    Task { @MainActor in
                        self.appState?.stopRecording()
                    }
                }
            } else {
                // Sound above noise floor detected — reset
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
