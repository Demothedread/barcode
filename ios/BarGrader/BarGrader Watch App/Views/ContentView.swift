import SwiftUI

struct ContentView: View {
    @EnvironmentObject var watchState: WatchState
    
    var body: some View {
        ZStack {
            Color(hex: "0f0f1a").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Mode badge
                HStack {
                    Text(modeBadgeLabel)
                        .font(.caption2.weight(.heavy))
                        .foregroundColor(modeBadgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(modeBadgeColor.opacity(0.15))
                        .cornerRadius(6)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                ScrollView {
                    VStack(spacing: 12) {
                        // Status line
                        Text(watchState.statusText)
                            .font(.caption)
                            .foregroundColor(Color(hex: "8888aa"))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        // Answer preview (if available)
                        if !watchState.answerPreview.isEmpty {
                            Text(watchState.answerPreview)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .lineLimit(3)
                                .padding(8)
                                .background(Color(hex: "1a1a2e"))
                                .cornerRadius(8)
                        }
                        
                        // Main record button
                        Button {
                            if watchState.isRecording {
                                watchState.stopRecording()
                            } else {
                                watchState.startRecording()
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: watchState.isRecording ? "mic.fill" : "mic")
                                    .font(.title)
                                Text(watchState.isRecording ? "Stop" : "Record")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(watchState.isRecording ? Color.red : Color(hex: "e94560"))
                            .cornerRadius(12)
                        }
                        
                        // Playback controls (if speaking)
                        if watchState.isSpeaking || !watchState.answerPreview.isEmpty {
                            HStack(spacing: 4) {
                                Button {
                                    watchState.togglePause()
                                } label: {
                                    Image(systemName: watchState.isPaused ? "play.fill" : "pause.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(Color(hex: "222240"))
                                        .cornerRadius(8)
                                }
                                
                                Button {
                                    watchState.repeatAnswer()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(Color(hex: "222240"))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        
                        // Additional controls
                        HStack(spacing: 4) {
                            Button {
                                watchState.cycleMode()
                            } label: {
                                Image(systemName: "arrow.right.circle")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(Color(hex: "333355"))
                                    .cornerRadius(6)
                            }
                            
                            Button {
                                watchState.increaseSpeed()
                            } label: {
                                Image(systemName: "hare")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(Color(hex: "333355"))
                                    .cornerRadius(6)
                            }
                        }
                        
                        // Reset
                        Button {
                            watchState.resetSession()
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .font(.caption)
                                .foregroundColor(Color(hex: "8888aa"))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(Color(hex: "222240"))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    private var modeBadgeLabel: String {
        switch watchState.currentMode {
        case "outline": return "OUTLINE"
        case "mbe":     return "MBE"
        default:        return "ESSAY"
        }
    }
    
    private var modeBadgeColor: Color {
        switch watchState.currentMode {
        case "outline": return Color(hex: "ffa502")
        case "mbe":     return Color(hex: "e94560")
        default:        return Color(hex: "4ecdc4")
        }
    }
}

// MARK: - Hex Color Helper

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

#Preview {
    ContentView()
        .environmentObject(WatchState.shared)
}
