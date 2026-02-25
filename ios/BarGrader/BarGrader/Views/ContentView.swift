import SwiftUI

/// Main app view — clean, intuitive interface for bar exam practice
struct ContentView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        ZStack {
            Color(hex: "0f0f1a").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HeaderView()
                
                // Main content area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Status
                            StatusBanner()
                            
                            // Waveform (when recording)
                            if state.isRecording {
                                WaveformView()
                                    .frame(height: 60)
                                    .transition(.opacity)
                            }
                            
                            // Transcript bubble
                            if !state.transcript.isEmpty {
                                TranscriptBubble(text: state.transcript)
                            }
                            
                            // Answer
                            if !state.answerText.isEmpty {
                                AnswerView(text: state.answerText)
                                    .id("answerBottom")
                            }
                            
                            // Playback controls
                            if state.isAnswerComplete || state.isSpeaking {
                                PlaybackControls()
                            }
                            
                            // Outline → Essay confirmation
                            if state.awaitingEssayConfirm {
                                OutlineConfirmView()
                            }
                            
                            // New Question button (visible when answer is complete)
                            if state.isAnswerComplete {
                                Button {
                                    state.resetSession()
                                } label: {
                                    Label("New Question", systemImage: "arrow.counterclockwise.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(hex: "e94560"))
                                        .cornerRadius(12)
                                }
                                .padding(.top, 4)
                            }
                            
                            Spacer(minLength: 20)
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: state.answerText) { _ in
                        withAnimation {
                            proxy.scrollTo("answerBottom", anchor: .bottom)
                        }
                    }
                }
                
                // Input area
                InputArea()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.isRecording)
        .sheet(isPresented: $state.showSettings) {
            SettingsView()
                .environmentObject(state)
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    @EnvironmentObject var state: AppState
    
    private var modeBadgeLabel: String {
        switch state.currentMode {
        case "outline":   return "OUTLINE"
        case "mbe":       return "MBE"
        case "quickhits": return "QUICK HITS"
        case "mbequiz":   return "MBE QUIZ"
        default:          return "ESSAY"
        }
    }

    private var modeBadgeColor: Color {
        switch state.currentMode {
        case "outline":   return Color(hex: "ffa502")
        case "mbe":       return Color(hex: "e94560")
        case "quickhits": return Color(hex: "00d2ff")
        case "mbequiz":   return Color(hex: "a855f7")
        default:          return Color(hex: "4ecdc4")
        }
    }

    var body: some View {
        HStack {
            Text("Bartender")
                .font(.title3.bold())
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "e94560"), Color(hex: "ff6b6b")],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            
            // Mode badge
            Text(modeBadgeLabel)
                .font(.caption2.weight(.heavy))
                .foregroundColor(modeBadgeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(modeBadgeColor.opacity(0.15))
                .cornerRadius(6)
            
            // Offline indicator
            if state.isOfflineMode || !state.isConnected {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.slash.fill")
                        .font(.caption2)
                    Text("OFFLINE")
                        .font(.caption2.weight(.heavy))
                }
                .foregroundColor(Color(hex: "ffa502"))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(hex: "ffa502").opacity(0.15))
                .cornerRadius(6)
            }
            
            Spacer()
            
            // Connection badge
            HStack(spacing: 4) {
                Circle()
                    .fill(state.isConnected ? Color.green : (state.localLLM.isModelLoaded ? Color(hex: "ffa502") : Color.red))
                    .frame(width: 6, height: 6)
                Text(state.isConnected ? "Connected" :
                        (state.localLLM.isModelLoaded ? "Local LLM" : "Offline"))
                    .font(.caption2)
                    .foregroundColor(state.isConnected ? .green :
                                        (state.localLLM.isModelLoaded ? Color(hex: "ffa502") : .red))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "222240"))
            .cornerRadius(12)
            
            Button {
                state.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(Color(hex: "8888aa"))
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "1a1a2e"))
    }
}

// MARK: - Status Banner

struct StatusBanner: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        HStack(spacing: 8) {
            if state.isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Color(hex: "ffa502"))
            }
            Text(state.statusText)
                .font(.subheadline)
                .foregroundColor(state.isProcessing ? Color(hex: "ffa502") : Color(hex: "8888aa"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Waveform Animation

struct WaveformView: View {
    @State private var animating = false
    let barCount = 12
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "e94560"))
                    .frame(width: 4)
                    .frame(height: animating ? CGFloat.random(in: 10...45) : 8)
                    .animation(
                        .easeInOut(duration: 0.3 + Double(i) * 0.05)
                        .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}

// MARK: - Transcript Bubble

struct TranscriptBubble: View {
    let text: String
    
    var body: some View {
        Text("\"\(text)\"")
            .font(.subheadline)
            .italic()
            .foregroundColor(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "0f3460"))
            .cornerRadius(12)
    }
}

// MARK: - Answer View

struct AnswerView: View {
    let text: String
    
    var body: some View {
        Text(attributedAnswer(text))
            .font(.system(size: 15, design: .default))
            .lineSpacing(6)
            .foregroundColor(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "1a1a2e"))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "333355"), lineWidth: 0.5)
            )
    }
    
    /// Simple attributed string for IRAC formatting
    private func attributedAnswer(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        // Bold markers like **ISSUE** **RULE** etc.
        // SwiftUI AttributedString has limited markdown, so we use it directly
        if let md = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            attr = md
        }
        return attr
    }
}

// MARK: - Playback Controls

struct PlaybackControls: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                state.repeatAnswer()
            } label: {
                Label("Repeat", systemImage: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(ControlButtonStyle())
            
            Button {
                state.togglePause()
            } label: {
                Label(state.isPaused ? "Resume" : "Pause",
                      systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption)
            }
            .buttonStyle(ControlButtonStyle())
            
            Button {
                state.stopSpeaking()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.caption)
            }
            .buttonStyle(ControlButtonStyle())
            
            // Speed indicator
            Text("\(state.ttsSpeed, specifier: "%.1f")x")
                .font(.caption.bold())
                .foregroundColor(Color(hex: "e94560"))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(hex: "222240"))
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(hex: "222240"))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "333355"), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Input Area

struct InputArea: View {
    @EnvironmentObject var state: AppState
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Mode toggle
            HStack(spacing: 0) {
                ModeButton(title: "Voice", icon: "mic.fill", mode: .voice)
                ModeButton(title: "Keyboard", icon: "keyboard", mode: .keyboard)
            }
            .background(Color(hex: "222240"))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "333355"), lineWidth: 0.5)
            )
            
            // Input row
            HStack(spacing: 8) {
                // Text field (always present, but more prominent in keyboard mode)
                TextField("Type your question...", text: $state.typedText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .font(.body)
                    .padding(12)
                    .background(Color(hex: "222240"))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isTextFieldFocused ? Color(hex: "e94560") : Color(hex: "333355"),
                                lineWidth: 1
                            )
                    )
                    .lineLimit(1...5)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        if !state.typedText.isEmpty {
                            state.sendText(state.typedText)
                        }
                    }
                
                // Mic button (voice mode)
                if state.inputMode == .voice {
                    Button {
                        if state.isRecording {
                            state.stopRecording()
                        } else {
                            state.startRecording()
                        }
                    } label: {
                        Image(systemName: state.isRecording ? "mic.fill" : "mic")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(state.isRecording ? Color.red : Color(hex: "e94560"))
                            .clipShape(Circle())
                    }
                    .if(state.isRecording) { view in
                        view.overlay(
                            Circle()
                                .stroke(Color.red, lineWidth: 2)
                                .scaleEffect(1.3)
                                .opacity(0)
                                .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: state.isRecording)
                        )
                    }
                }
                
                // Send button
                Button {
                    state.sendText(state.typedText)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Color(hex: "0f3460"))
                        .clipShape(Circle())
                }
                .disabled(state.typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(state.typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            
            // Hint text
            Text(state.inputMode == .voice
                 ? "Tap mic or say \"\(state.wakeWord)\" • BT clicker: Play to record"
                 : "Type and press Return to send • BT keyboard supported")
                .font(.caption2)
                .foregroundColor(Color(hex: "8888aa"))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "1a1a2e"))
    }
}

struct ModeButton: View {
    @EnvironmentObject var state: AppState
    let title: String
    let icon: String
    let mode: InputMode
    
    var body: some View {
        Button {
            state.inputMode = mode
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption.weight(.medium))
            .foregroundColor(state.inputMode == mode ? .white : Color(hex: "8888aa"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(state.inputMode == mode ? Color(hex: "0f3460") : .clear)
            .cornerRadius(8)
        }
    }
}

// MARK: - Outline → Essay Confirmation

struct OutlineConfirmView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Would you like me to write the full essay from this outline?")
                .font(.subheadline)
                .foregroundColor(Color(hex: "ffa502"))
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button {
                    state.confirmEssayFromOutline()
                } label: {
                    Text("Yes, Write Essay")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(hex: "0f3460"))
                        .cornerRadius(10)
                }
                
                Button {
                    state.awaitingEssayConfirm = false
                    state.statusText = "Outline kept. Ask another question or say 'start over'."
                } label: {
                    Text("No, Keep Outline")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Color(hex: "8888aa"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(hex: "222240"))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(hex: "333355"), lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(14)
        .background(Color(hex: "1a1a2e"))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "ffa502").opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
