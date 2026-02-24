import Foundation

/// Manages the WebSocket connection to the Bartender backend server.
/// Handles reconnection, message parsing, and sending audio/text.
@MainActor
final class WebSocketService: NSObject, URLSessionWebSocketDelegate {
    private weak var appState: AppState?
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession!
    private var isConnecting = false
    private var reconnectTimer: Timer?
    
    init(appState: AppState) {
        self.appState = appState
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }
    
    // MARK: - Connection
    
    func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        
        guard let appState = appState else { return }
        let urlString = appState.serverURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
        
        guard let url = URL(string: "\(urlString)/ws") else {
            print("[WS] Invalid URL: \(urlString)")
            isConnecting = false
            return
        }
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessage()
    }
    
    func disconnect() {
        reconnectTimer?.invalidate()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        Task { @MainActor in
            appState?.isConnected = false
        }
    }
    
    // MARK: - Sending
    
    func sendText(_ text: String) {
        let msg: [String: Any] = ["type": "text", "text": text]
        sendJSON(msg)
    }
    
    func sendAudio(_ data: Data) {
        let base64 = data.base64EncodedString()
        let msg: [String: Any] = ["type": "audio", "audio": base64]
        sendJSON(msg)
    }
    
    func sendRepeat(_ section: String) {
        let msg: [String: Any] = ["type": "repeat", "section": section]
        sendJSON(msg)
    }
    
    func sendReset() {
        sendJSON(["type": "reset"])
    }
    
    func sendPing() {
        sendJSON(["type": "ping"])
    }
    
    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(str)) { error in
            if let error = error {
                print("[WS] Send error: \(error)")
            }
        }
    }
    
    // MARK: - Receiving
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default: break
                }
                self?.receiveMessage() // Continue listening
                
            case .failure(let error):
                print("[WS] Receive error: \(error)")
                self?.scheduleReconnect()
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        Task { @MainActor [weak self] in
            guard let appState = self?.appState else { return }
            
            switch type {
            case "status":
                appState.handleStatus(json["text"] as? String ?? "")
            case "transcript":
                appState.handleTranscript(json["text"] as? String ?? "")
            case "token":
                appState.handleToken(json["text"] as? String ?? "")
            case "tts":
                appState.handleTTSAudio(json["audio_base64"] as? String ?? "")
            case "section_pause":
                let seconds = json["seconds"] as? Double ?? 5.0
                appState.handleSectionPause(seconds: seconds)
            case "done":
                appState.handleDone(json["text"] as? String ?? "")
            case "tts_prompt":
                appState.handleStatus(json["text"] as? String ?? "")
            case "outline_prompt":
                appState.handleOutlinePrompt(json["text"] as? String ?? "")
            case "mode_change":
                let mode = json["mode"] as? String ?? "essay"
                let modeText = json["text"] as? String ?? ""
                appState.handleModeChange(mode: mode, text: modeText)
            case "reset_ack":
                appState.handleResetAck(json["text"] as? String ?? "Session cleared.")
            case "error":
                appState.handleError(json["text"] as? String ?? "")
            case "pong":
                break
            default:
                print("[WS] Unknown message type: \(type)")
            }
        }
    }
    
    // MARK: - Reconnection
    
    private func scheduleReconnect() {
        Task { @MainActor in
            appState?.isConnected = false
            appState?.statusText = "Disconnected. Reconnecting..."
        }
        isConnecting = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.connect()
        }
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        print("[WS] Connected")
        isConnecting = false
        Task { @MainActor in
            appState?.isConnected = true
            appState?.statusText = "Connected. Ready."
        }
        // Start keepalive ping
        schedulePing()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[WS] Closed: \(closeCode)")
        scheduleReconnect()
    }
    
    private func schedulePing() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self = self else { return }
            self.sendPing()
            self.schedulePing()
        }
    }
}
