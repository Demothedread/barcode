# BarGrader – California Bar Exam AI Essay Tutor

A native iOS app + Python backend that gives you AI-powered, IRAC-formatted answers to California Bar Exam essay questions — via voice or Bluetooth keyboard — with real-time text-to-speech output at controllable speed.

## Architecture

```
┌─────────────────────────────────┐
│   iPhone (Native iOS App)        │
│  ┌────────────────────────────┐  │
│  │  SwiftUI Interface         │  │
│  │  • Voice input (mic/dongle)│  │
│  │  • BT keyboard input       │  │
│  │  • Wake word detection      │  │
│  │  • Lock screen controls     │  │
│  │  • TTS playback             │  │
│  │  • Essay / Outline modes    │  │
│  └─────────┬──────────────────┘  │
│            │ WebSocket            │
└────────────┼─────────────────────┘
             │
┌────────────┼─────────────────────┐
│   Mac Server (FastAPI)           │
│  ┌─────────▼──────────────────┐  │
│  │  WebSocket Handler         │  │
│  │  • Whisper STT             │  │
│  │  • Shorthand expansion     │  │
│  │  • RAG retrieval           │  │
│  │  • LLM streaming           │  │
│  │  • TTS generation (80 WPM) │  │
│  │  • Session state / modes   │  │
│  └─────────┬──────────────────┘  │
│  ┌─────────▼──────────────────┐  │
│  │  RAG (dual backend)        │  │
│  │  • OpenAI Vector Stores    │  │
│  │  • ChromaDB (offline)      │  │
│  └────────────────────────────┘  │
│  ┌────────────────────────────┐  │
│  │  LLM Fallback Chain        │  │
│  │  OpenAI → Gemini → Grok   │  │
│  │  → GitHub/Claude → local   │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

## Features

### iOS App (Native Swift)
- **Voice Input**: Tap mic or say the wake word to start dictating your question
- **USB-C Dongle Mic**: Full support for external mics via Lightning/USB-C adapters
- **Lock Screen Control**: Bluetooth clicker triggers recording/playback from lock screen
- **Bluetooth Keyboard**: Full keyboard support with shortcuts for hands-free operation
- **Wake Word**: Customizable activation phrase (default: "hey bargrader")
- **Auto-send on Silence**: Detects when you stop speaking and auto-submits
- **High Mic Sensitivity**: Captures whisper-level speech with gain boosting
- **TTS Playback**: Streams the answer aloud at ~80 WPM with 5s section pauses
- **Pause/Resume/Repeat**: Full playback controls from app and lock screen
- **Essay / Outline Modes**: Say "outline only" for quick issue-spotting, then confirm for full essay
- **Session Reset**: Say "next question" / "start over" to clear context

### Backend Server
- **RAG-Enhanced**: Dual-backend retrieval (OpenAI Vector Stores primary, ChromaDB offline)
- **IRAC Format**: All answers structured as Issue → Rule → Application → Conclusion per `essay_instruct.md`
- **Nested IRAC**: Sub-issues get their own IR(irac)C analysis
- **Streaming**: Tokens stream in real-time as the LLM generates
- **LLM Fallback Chain**: OpenAI → Gemini → Grok (xAI) → GitHub Models (Claude) → local llama.cpp
- **Shorthand Expansion**: Automatically expands legal abbreviations (K=contract, D=defendant, SOF, etc.)
- **Whisper STT**: Server-side transcription tuned for legal terminology
- **OpenAI TTS**: Voice output at ~80 WPM with [SECTION_BREAK] pauses between IRAC sections
- **Offline Mode**: Local llama.cpp + ChromaDB when no internet is available

### Apple Watch Companion App (watchOS)
- **Wireless Control**: Tap record button on your wrist to start dictating questions
- **Real-time Status**: Watch displays: "🎙️ Listening...", "Processing...", "Streaming answer..."
- **Answer Preview**: Shows first 2 lines of the IRAC response on the watch screen
- **Full Playback Control**: Pause/resume, repeat, speed up (⏸️ ▶️ 🔄 🐇)
- **Mode Sync**: Watch displays current mode badge (ESSAY/OUTLINE/MBE)
- **iPhone Pairing**: WatchConnectivity sends commands to iPhone; iPhone does all heavy lifting (recording, LLM, TTS)
- **Battery Efficient**: Watch is control surface only; background TTS continues on iPhone
- **No Keyboard Input**: Voice-only on watch (full Bluetooth keyboard on iPhone)

### Bluetooth Controls (Lock Screen)
| Button | Action |
|--------|--------|
| **Play** | Start recording your question |
| **Pause** | Stop recording / Pause TTS playback |
| **Next Track** | Repeat the answer |
| **Previous Track** | Increase speaking speed |
| **Stop** | Cancel everything / Cycle mode (when idle) |

### Keyboard Shortcuts (BT Keyboard)

| Key | Action |
|-----|--------|
| **Return** | Send typed question |
| **Escape** | Stop recording / Cancel |
| **Space** (unfocused) | Toggle microphone |
| **Page Up/Down** | Speed ±0.1x |
| **F1** | Repeat answer |
| **F2** | Pause/Resume |
| **F3** | Stop playback |

## Quick Start

### 1. Clone & Setup
```bash
cd /path/to/bargrader
./setup.sh
```

### 2. Configure API Keys
Edit `.env` (primary keys) and `.env.local` (vector store IDs):

```bash
cd /path/to/bargrader
nano .env
# optional:
nano .env.local
```
# .env — at minimum:
OPENAI_API_KEY=sk-your-key-here

# Optional backup providers:
GEMINI_API_KEY=your-gemini-key
GROK_API_KEY=xai-your-key        # free tier at console.x.ai
GITHUB_TOKEN=ghp_your-pat         # needs `models` scope for Claude

# .env.local — OpenAI Vector Store IDs (from platform.openai.com):
OPENAI_VECTOR_ESSAY_EXEMPLARY=vs_...
OPENAI_VECTOR_SOURCE=vs_...
OPENAI_VECTOR_ESSAY_ATTACK=vs_...
```

### 3. Add Study Materials (for ChromaDB offline mode)
Place your CA bar exam documents in `data/bar_exam_docs/`:
- PDF outlines (Barbri, Themis, etc.)
- Practice essay questions & model answers
- Rule summaries, California code excerpts
- Any `.pdf`, `.txt`, `.docx`, `.md` files

### 4. Start the Server
```bash
./start_server.sh
```
Note the URL displayed (e.g., `http://192.168.1.100:8080`)

### 5. Build the iOS App
```bash
# If you have xcodegen:
./setup_xcode.sh

# Or create manually in Xcode:
# 1. New iOS App → SwiftUI → BarGrader
# 2. Copy all files from ios/BarGrader/BarGrader/ into the project
Enables the app to continue limited work while in the background by turning on the **Audio** and **Background fetch** modes.

### How to add it (iOS)
1. Open the iOS project in **Xcode**.
2. Select the app target → **Signing & Capabilities**.
3. Click **+ Capability** and add **Background Modes**.
4. In the Background Modes list, check:
    - **Audio, AirPlay, and Picture in Picture**
    - **Background fetch**

### What this changes
Xcode updates the app entitlements/Info.plist with `UIBackgroundModes`, typically including:
- `audio`
- `fetch`

### Important follow-up
Enabling the capability alone is not enough:
- Implement background fetch handling in app code (e.g., AppDelegate/background task APIs).
- Keep background work minimal and battery-friendly.
- Test on a real device, since simulator behavior can differ.
# 3. Add Background Modes capability (Audio + Background fetch)
# 4. Build to your iPhone
```

### 6. Connect
1. Open BarGrader on your iPhone
2. Go to Settings (gear icon)
3. Set the Server URL to your Mac's address
4. Plug in your USB-C dongle mic if using external audio
5. Start asking questions!

### 6b. Build the Apple Watch Companion (Optional)
1. In Xcode, add a new **watchOS App Target:**
   - File → New → Target
   - Select "Watch App" (not "Watch App for iOS App")
   - Choose SwiftUI
   - Name it "BarGrader Watch App"
2. Copy the files from `ios/BarGrader/BarGrader Watch App/` into the new target
3. Enable **WatchKit entitlements** on both targets (Xcode will auto-prompt)
4. Build to your paired Apple Watch (Series 6 or later)
5. When you open the iPhone app, watch will auto-sync via WatchConnectivity

The watch companion runs independently:
- **Large record button** on the watch face to start dictating
- **Status display** shows what's happening
- **Playback controls** let you pause/repeat/speed up from your wrist
- **iPhone does all the work**: your watch just sends commands and receives status updates

## iPhone Setup Tips


### Keeping the App Alive
The app uses **Background Audio mode** to stay alive. As long as it has an active audio session (recording or playing), iOS won't suspend it. The app automatically maintains this.

### Bluetooth Clicker Setup
1. Pair your Bluetooth clicker/remote with your iPhone
2. The clicker's media buttons map to BarGrader controls automatically
3. Works even from the lock screen via `MPRemoteCommandCenter`

### Network Requirements
- iPhone and Mac must be on the same WiFi network
- Alternatively, use **Tailscale** or **ngrok** for remote access
- For Tailscale: set `SERVER_URL` to your Tailscale IP

## File Structure

```
bargrader/
├── backend/
│   ├── app.py              # FastAPI server + WebSocket handler + session state
│   ├── config.py           # Settings, fallback chain, dual .env loading
│   ├── rag_engine.py       # Dual RAG: OpenAI Vector Stores + ChromaDB
│   ├── llm_client.py       # Multi-provider LLM streaming + Whisper + TTS
│   ├── prompts.py          # IRAC system prompt engineering + mode detection
│   └── instructions/
│       ├── essay_instruct.md   # CA bar essay writing rules (loaded at boot)
│       └── outline_instruct.md # Terse outline mode instructions
├── frontend/               # PWA fallback (also works in Safari)
│   ├── index.html
│   ├── manifest.json
│   └── sw.js
├── ios/BarGrader/BarGrader/
│   ├── BarGraderApp.swift  # App entry + audio session config
│   ├── Models/
│   │   └── AppState.swift  # Central state (mode, session, outline confirm)
│   ├── Views/
│   │   ├── ContentView.swift   # Main UI + outline confirm + mode badge
│   │   └── SettingsView.swift  # Settings panel
│   ├── Services/
│   │   ├── WebSocketService.swift        # WS connection + message routing
│   │   ├── AudioRecorderService.swift    # Mic recording + silence detection
│   │   ├── SpeechRecognitionService.swift # Live transcription
│   │   ├── TTSPlaybackService.swift      # Audio queue + section pause handling
│   │   ├── RemoteCommandService.swift    # Lock screen / BT controls
│   │   └── WakeWordService.swift         # Always-on wake word listener
│   ├── Info.plist
│   └── BarGrader.entitlements
├── tests/                  # pytest test suite
│   ├── conftest.py         # Shared fixtures + env isolation
│   ├── test_config.py
│   ├── test_prompts.py
│   ├── test_llm_client.py
│   ├── test_rag_engine.py
│   └── test_app.py
├── data/
│   └── bar_exam_docs/      # Your study materials go here
├── .env.example
├── .env.local              # Vector store IDs (git-ignored)
├── requirements.txt
├── pyproject.toml          # pytest config
├── setup.sh                # One-time setup
├── start_server.sh         # Start the backend
└── setup_xcode.sh          # Generate Xcode project
```

## How It Works

1. **You speak or type** a bar exam essay question (including via USB-C dongle mic)
2. **Audio** is sent to the server via WebSocket, transcribed by **Whisper**
3. **Shorthand** is expanded (K→contract, D→defendant, SOF→Statute of Frauds, etc.)
4. **RAG** retrieves relevant rules from OpenAI Vector Stores (or local ChromaDB)
5. The question + context is sent through the **LLM fallback chain** with the IRAC system prompt
6. **Tokens stream back** to the iPhone in real-time (you see the text appear)
7. **TTS audio** is generated sentence-by-sentence at ~80 WPM with 5s section pauses
8. When done, the app asks if you want any section repeated
9. Say **"outline only"** for quick issue-spotting; then **"yes"** for the full essay

## Requirements

- **Mac**: Python 3.10+
- **iPhone**: iOS 16+, optional USB-C dongle mic
- **API Key**: OpenAI (required for Whisper STT + TTS); backup LLM keys optional
- **Network**: Same WiFi or VPN between iPhone and Mac
- **Optional**: ChromaDB + 4GB RAM (only for local RAG; not needed with OpenAI Vector Stores)

## License

Personal use only. Study materials you add are your own.
