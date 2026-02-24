import SwiftUI

/// Settings panel — configure TTS speed, voice, mic, wake word, server URL
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // ---- Speech Output ----
                Section("Speech Output") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Speaking Speed")
                            Spacer()
                            Text("\(state.ttsSpeed, specifier: "%.1f")x")
                                .foregroundColor(Color(hex: "e94560"))
                                .font(.subheadline.bold())
                        }
                        Slider(value: $state.ttsSpeed, in: 0.5...2.0, step: 0.1)
                            .tint(Color(hex: "e94560"))
                        HStack {
                            Text("Slow").font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text("Fast").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    
                    Picker("Voice", selection: $state.ttsVoice) {
                        Text("Nova (female)").tag("nova")
                        Text("Alloy (neutral)").tag("alloy")
                        Text("Echo (male)").tag("echo")
                        Text("Fable (expressive)").tag("fable")
                        Text("Onyx (deep male)").tag("onyx")
                        Text("Shimmer (warm)").tag("shimmer")
                    }
                }
                
                // ---- Microphone ----
                Section("Microphone") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Silence Detection")
                            Spacer()
                            Text(state.silenceThreshold == 0 ? "Manual" : "\(state.silenceThreshold, specifier: "%.1f")s")
                                .foregroundColor(Color(hex: "e94560"))
                                .font(.subheadline.bold())
                        }
                        Slider(value: $state.silenceThreshold, in: 0...10.0, step: 0.5)
                            .tint(Color(hex: "e94560"))
                        Text(state.silenceThreshold == 0
                             ? "Manual mode — tap Stop when you're done speaking. Best for long essays."
                             : "Auto-sends after \(state.silenceThreshold, specifier: "%.1f")s of silence. Set to 0 for manual stop.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("Mic Sensitivity", selection: $state.micSensitivity) {
                        Text("High (whisper-level)").tag("high")
                        Text("Medium").tag("medium")
                        Text("Low (normal voice)").tag("low")
                    }
                }
                
                // ---- Connected Devices ----
                Section("Connected Devices") {
                    // Lav Mic / Input
                    HStack {
                        Label("Input", systemImage: "mic.fill")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(state.isLavMicDetected ? Color.green : Color(hex: "8888aa"))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(state.detectedInputName)
                                    .foregroundColor(state.isLavMicDetected ? .green : .secondary)
                                    .font(.caption)
                                Text(AppState.portLabel(state.detectedInputType))
                                    .foregroundColor(.secondary)
                                    .font(.caption2)
                            }
                        }
                    }
                    
                    // Headphones / Output
                    HStack {
                        Label("Output", systemImage: "headphones")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(state.isHeadphonesDetected ? Color.green : Color(hex: "8888aa"))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(state.detectedOutputName)
                                    .foregroundColor(state.isHeadphonesDetected ? .green : .secondary)
                                    .font(.caption)
                                Text(AppState.portLabel(state.detectedOutputType))
                                    .foregroundColor(.secondary)
                                    .font(.caption2)
                            }
                        }
                    }
                    
                    // BT Clicker
                    HStack {
                        Label("Clicker", systemImage: "button.programmable")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(state.isClickerDetected ? Color.green : Color(hex: "8888aa"))
                                .frame(width: 8, height: 8)
                            Text(state.isClickerDetected ? "Paired" : "Not Detected")
                                .foregroundColor(state.isClickerDetected ? .green : .secondary)
                                .font(.caption)
                        }
                    }
                    
                    Button {
                        state.refreshAudioRoutes()
                    } label: {
                        Label("Refresh Devices", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(hex: "e94560"))
                    }
                    
                    if !state.isLavMicDetected {
                        Text("Plug in your USB-C lav mic receiver. It will be auto-detected.")
                            .font(.caption)
                            .foregroundColor(Color(hex: "ffa502"))
                    }
                }
                
                // ---- Input Methods ----
                Section {
                    // Wake Word
                    Toggle(isOn: $state.useWakeWord) {
                        Label("Wake Word", systemImage: "waveform.circle")
                    }
                    .tint(Color(hex: "e94560"))
                    
                    if state.useWakeWord {
                        HStack {
                            Text("Phrase")
                            Spacer()
                            TextField("e.g., hey bartender", text: $state.wakeWord)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(Color(hex: "e94560"))
                        }
                    }
                    
                    // Siri Shortcut
                    Toggle(isOn: $state.useSiriShortcut) {
                        Label("Siri Shortcut", systemImage: "mic.badge.plus")
                    }
                    .tint(Color(hex: "e94560"))
                    
                    if state.useSiriShortcut {
                        Text("Say \"Hey Siri, Ask Bartender\" to start recording hands‑free.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // BT Clicker – greyed when not connected
                    HStack {
                        Label("Bluetooth Clicker", systemImage: "button.programmable")
                        Spacer()
                        if state.isClickerDetected {
                            Text("Connected")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Text("Not Detected")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .opacity(state.isClickerDetected ? 1.0 : 0.45)
                    
                    // Apple Watch – greyed when not paired
                    HStack {
                        Label("Apple Watch", systemImage: "applewatch")
                        Spacer()
                        if state.isWatchAvailable {
                            Text("Paired")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Text("Unavailable")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .opacity(state.isWatchAvailable ? 1.0 : 0.45)
                    
                    // Auto-Start Recording
                    Toggle(isOn: $state.autoStartRecording) {
                        Label("Auto‑Start Recording", systemImage: "record.circle")
                    }
                    .tint(Color(hex: "e94560"))
                    
                    Text("Automatically begin recording when the app launches.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Input Methods")
                } footer: {
                    Text("Greyed-out options require hardware that isn't currently connected.")
                        .font(.caption2)
                }
                
                // ---- Output ----
                Section("Output") {
                    Toggle(isOn: $state.immediateTTSPlayback) {
                        Label("Immediate TTS Playback", systemImage: "speaker.wave.3.fill")
                    }
                    .tint(Color(hex: "e94560"))
                    
                    Text("Speak the answer aloud as soon as grading completes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Toggle(isOn: $state.useSilentAudioSession) {
                        Label("Silent Audio Session", systemImage: "speaker.slash.fill")
                    }
                    .tint(Color(hex: "ffa502"))
                    
                    Text("Keep mic active without speaker output. TTS is suppressed; answers appear on-screen only.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // ---- Clicker / Keyboard Controls Reference ----
                Section("Controls Reference") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bluetooth Clicker")
                            .font(.subheadline.bold())
                        Group {
                            Label("Play → Start recording", systemImage: "play.circle")
                            Label("Pause → Stop recording / Pause TTS", systemImage: "pause.circle")
                            Label("Stop (idle) → Cycle mode (Essay/Outline/MBE)", systemImage: "stop.circle")
                            Label("Stop (active) → Stop everything", systemImage: "xmark.circle")
                            Label("Next → Repeat answer", systemImage: "forward.circle")
                            Label("Previous → Speed up", systemImage: "backward.circle")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                // ---- Server ----
                Section("Server Connection") {
                    HStack {
                        Text("Server URL")
                        Spacer()
                        TextField("http://192.168.1.x:8080", text: $state.serverURL)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(Color(hex: "e94560"))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                    
                    Button("Reconnect") {
                        state.webSocketService.disconnect()
                        state.connectIfNeeded()
                    }
                    .foregroundColor(Color(hex: "e94560"))
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(state.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(state.isConnected ? "Connected" : "Disconnected")
                                .foregroundColor(state.isConnected ? .green : .red)
                        }
                    }
                }
                
                // ---- Offline / On-Device LLM ----
                Section("Offline Mode") {
                    Toggle("Force Offline", isOn: $state.isOfflineMode)
                        .tint(Color(hex: "ffa502"))
                    
                    Text("When enabled, all queries use the on-device model instead of the server. Useful for testing or no-network scenarios.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("Local Model")
                        Spacer()
                        if state.localLLM.isModelLoaded {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Loaded")
                                    .foregroundColor(.green)
                            }
                        } else if state.localLLM.downloadProgress > 0 && state.localLLM.downloadProgress < 1.0 {
                            HStack(spacing: 4) {
                                ProgressView(value: state.localLLM.downloadProgress)
                                    .frame(width: 60)
                                    .tint(Color(hex: "ffa502"))
                                Text("\(Int(state.localLLM.downloadProgress * 100))%")
                                    .foregroundColor(Color(hex: "ffa502"))
                                    .font(.caption)
                            }
                        } else if let error = state.localLLM.loadError {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Text("Error")
                                    .foregroundColor(.red)
                            }
                        } else {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Loading...")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    HStack {
                        Text("Model File")
                        Spacer()
                        Text(LocalLLMService.bundledModelName)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    if state.localLLM.loadError != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Offline model will auto-download on first launch (~1.1 GB).")
                                .font(.caption.bold())
                                .foregroundColor(Color(hex: "ffa502"))
                            Text("Requires WiFi for initial download. After that, works fully offline.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button {
                                state.localLLM.preloadModel()
                            } label: {
                                Label("Retry Download", systemImage: "arrow.clockwise.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(hex: "e94560"))
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    if state.localLLM.isGenerating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Generating response...")
                                .font(.caption)
                                .foregroundColor(Color(hex: "ffa502"))
                        }
                    }
                }
                
                // ---- Keyboard ----
                Section("Bluetooth Keyboard") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keyboard Shortcuts")
                            .font(.subheadline.bold())
                        Group {
                            Label("Return → Send question", systemImage: "return")
                            Label("Escape → Stop/Cancel", systemImage: "escape")
                            Label("Space (unfocused) → Toggle mic", systemImage: "space")
                            Label("Page Up/Down → Speed ±0.1x", systemImage: "arrow.up.arrow.down")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                // ---- About ----
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    Text("Bartender – AI-powered California Bar Exam essay tutor using IRAC methodology with RAG-enhanced knowledge base.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Save settings to server
                        syncSettingsToServer()
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "e94560"))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func syncSettingsToServer() {
        guard let url = URL(string: "\(state.serverURL)/api/settings") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "tts_speed": state.ttsSpeed,
            "tts_voice": state.ttsVoice,
            "silence_threshold": state.silenceThreshold,
            "wake_word": state.wakeWord,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                print("[Settings] Sync error: \(error)")
            }
        }.resume()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
