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
                            Text("\(state.silenceThreshold, specifier: "%.1f")s")
                                .foregroundColor(Color(hex: "e94560"))
                                .font(.subheadline.bold())
                        }
                        Slider(value: $state.silenceThreshold, in: 0.5...5.0, step: 0.5)
                            .tint(Color(hex: "e94560"))
                        Text("How long to wait after you stop speaking before auto-sending")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("Mic Sensitivity", selection: $state.micSensitivity) {
                        Text("High (whisper-level)").tag("high")
                        Text("Medium").tag("medium")
                        Text("Low (normal voice)").tag("low")
                    }
                }
                
                // ---- Activation ----
                Section("Activation") {
                    HStack {
                        Text("Wake Word")
                        Spacer()
                        TextField("e.g., hey bargrader", text: $state.wakeWord)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(Color(hex: "e94560"))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bluetooth Clicker Controls")
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
                    Text("BarGrader – AI-powered California Bar Exam essay tutor using IRAC methodology with RAG-enhanced knowledge base.")
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
