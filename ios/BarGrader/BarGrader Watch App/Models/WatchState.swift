import Foundation
import SwiftUI
import WatchConnectivity

/// Watch companion state — minimal, status-only interface
@MainActor
final class WatchState: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchState()
    
    // MARK: - Published UI State
    @Published var statusText: String = "Ready"
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentMode: String = "essay"  // echo from iPhone
    @Published var answerPreview: String = ""     // first 2 lines of answer
    
    // MARK: - WatchConnectivity
    private var session: WCSession?
    
    private override init() {
        super.init()
        setupWatchConnectivity()
    }
    
    // MARK: - WatchConnectivity Setup
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
        print("[Watch] WatchConnectivity activated")
    }
    
    // MARK: - Actions (Watch → iPhone)
    
    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        statusText = "🎙️ Listening..."
        sendMessage(["action": "start_recording"])
    }
    
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        statusText = "Processing..."
        sendMessage(["action": "stop_recording"])
    }
    
    func togglePause() {
        if isPaused {
            statusText = "▶️ Resuming..."
        } else {
            statusText = "⏸️ Paused"
        }
        isPaused.toggle()
        sendMessage(["action": "toggle_pause"])
    }
    
    func repeatAnswer() {
        statusText = "🔄 Repeating..."
        sendMessage(["action": "repeat_answer"])
    }
    
    func increaseSpeed() {
        sendMessage(["action": "increase_speed"])
    }
    
    func resetSession() {
        statusText = "🔄 Resetting..."
        sendMessage(["action": "reset_session"])
    }
    
    func cycleMode() {
        sendMessage(["action": "cycle_mode"])
    }
    
    // MARK: - Message Passing
    
    private func sendMessage(_ message: [String: Any]) {
        guard let session = session, session.isReachable else {
            statusText = "⚠️ iPhone unreachable"
            return
        }
        session.sendMessage(message, replyHandler: nil) { error in
            print("[Watch] Message send error: \(error)")
        }
    }
    
    // MARK: - WCSessionDelegate (iPhone → Watch)
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("[Watch] Session activated: \(activationState.rawValue)")
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("[Watch] Session inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("[Watch] Session deactivated")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.handleMessage(message)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any],
                 replyHandler: @escaping ([String : Any]) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.handleMessage(message)
        }
        replyHandler(["status": "received"])
    }
    
    private func handleMessage(_ message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        
        switch type {
        case "status":
            statusText = message["text"] as? String ?? "..."
            
        case "recording":
            isRecording = message["recording"] as? Bool ?? false
            
        case "processing":
            isProcessing = message["processing"] as? Bool ?? false
            
        case "speaking":
            isSpeaking = message["speaking"] as? Bool ?? false
            isPaused = message["paused"] as? Bool ?? false
            
        case "mode_change":
            currentMode = message["mode"] as? String ?? "essay"
            
        case "answer_preview":
            answerPreview = message["preview"] as? String ?? ""
            
        default:
            print("[Watch] Unknown message type: \(type)")
        }
    }
}
