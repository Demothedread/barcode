# Bartender — California Bar Exam AI Tutor

Speak a bar exam question into your iPhone. Get an IRAC-formatted answer read back to you. Works online (Railway cloud) and offline (on-device LLM). One script to build and deploy.

---

## Quick Start

```bash
cd bargrader
./launch.sh
```

That's it. The script checks everything, installs dependencies, builds the app, and deploys to your connected iPhone. Read on for what to expect.

---

## What You Need

| Requirement | Details |
|-------------|---------|
| **Mac** | macOS 13+ with Xcode installed |
| **iPhone** | iOS 16+, connected via USB or same WiFi |
| **Apple ID** | Free or paid, signed into Xcode |
| **API Keys** | At minimum `OPENAI_API_KEY` in `.env` (for cloud mode) |

Optional: USB-C dongle mic, Bluetooth clicker/keyboard, Apple Watch.

---

## What `./launch.sh` Does

The script runs 6 steps. Here's exactly what you'll see:

### Step 1 — Environment Check

```
▸ 1/6  Checking environment
  ✔ Xcode: Xcode 16.2
  ✔ CLI tools: /Applications/Xcode.app/Contents/Developer
  ✔ Signing: Apple Development: you@email.com (XXXXXXXXXX)
  ✔ iPhone: Your iPhone (00008110-XXXXXXXXXXXX)
```

**If Xcode CLI tools aren't installed**: The script runs `xcode-select --install`. A macOS dialog appears:

> "The xcode-select command requires the command line developer tools. Would you like to install the tools now?"

Click **Install**, wait for it to finish, then re-run `./launch.sh`.

**If no signing identity is found**: Open Xcode → Settings (⌘,) → Accounts → click **+** → Add your Apple ID. Then re-run.

**If no iPhone is detected**: Connect via USB cable. Your iPhone will show:

> "Trust This Computer?"

Tap **Trust** and enter your passcode. Re-run the script.

### Step 2 — LLM.swift Package

```
▸ 2/6  Configuring LLM.swift package dependency
  ✔ LLM.swift already in project
```

Adds the [LLM.swift](https://github.com/eastriverlee/LLM.swift) Swift Package (llama.cpp wrapper) to the Xcode project. Runs once; skips on subsequent launches.

### Step 3 — Resolve Packages

```
▸ 3/6  Resolving Swift Package Manager dependencies
  ✔ Packages resolved
```

Downloads LLM.swift and its dependencies. Takes 30–60 seconds on first run.

### Step 4 — Build

```
▸ 4/6  Building Bartender for iPhone
  Building... (this may take 1-3 minutes on first run)
  ✔ Build succeeded
```

Compiles the app for your physical iPhone (not simulator). First build takes 1–3 minutes; incremental builds are faster.

**If the build fails**: The script shows the first 20 errors. Common fixes:
- "Signing requires a development team" → Open the `.xcodeproj` in Xcode, select the BarGrader target → Signing & Capabilities → pick your team
- "No provisioning profile" → Same place, enable "Automatically manage signing"

### Step 5 — Install

```
▸ 5/6  Installing on iPhone
  ✔ Built for Your iPhone — open Xcode to run (Cmd+R)
```

If `ios-deploy` is installed (`brew install ios-deploy`), it installs directly to the phone. Otherwise, open Xcode and press **⌘R**.

### Step 6 — Backend (optional)

```
▸ 6/6  Backend (skipped — use --server to push to Railway)
  Server: https://barcode-production-0db7.up.railway.app
```

To push backend changes to Railway:
```bash
./launch.sh --server
```

---

## First Launch on iPhone

When you open Bartender for the first time, iOS asks for three permissions in sequence:

### Permission 1: Microphone

> "Bartender needs your microphone to listen to your bar exam questions."

Tap **Allow**. Required for voice input.

### Permission 2: Speech Recognition

> "Bartender uses speech recognition for wake word detection."

Tap **Allow**. Required for the wake word ("hey bartender") and offline speech-to-text.

### Permission 3: Local Network

> "Bartender connects to a local server on your network for AI-powered grading."

Tap **Allow**. Used for local development; not needed when using Railway.

### What Happens Next

The app opens to a dark screen with a mic button at the bottom and "Ready" at the top.

**If you have internet**: The app connects to Railway automatically. The status dot in Settings turns green.

**If you're offline**: The app auto-downloads a 1.1 GB on-device model (SmolLM2-1.7B) on first use. This requires WiFi once. After that, everything works offline — no server needed.

---

## How to Use It

### Voice (default)

1. Tap the **mic button** (or say "hey bartender")
2. Ask your question: *"What are the elements of negligence under California law?"*
3. Wait for the silence detection to auto-send (2 seconds of silence)
4. Watch the IRAC answer stream in, then hear it read aloud

### Keyboard

1. Tap the **text field** at the bottom
2. Type your question
3. Press **Return** to send

### Modes

| Mode | How to activate | What you get |
|------|----------------|--------------|
| **Essay** | Default | Full IRAC analysis |
| **Outline** | Say "outline only" or cycle via Settings | Bullet-point issue spotting |
| **MBE** | Say "exam mode" or cycle via Settings | Answer letter + 1-2 sentence explanation |

After an outline, the app asks: *"Would you like the full essay?"* — say "yes" or ask a new question.

---

## Architecture

```
┌─────────────────────────────────────────┐
│         iPhone (Bartender.app)           │
│                                         │
│  Voice ──→ STT ──→ Question             │
│                        │                │
│            ┌───────────┼────────────┐   │
│            │ Online?   │            │   │
│            │           ▼            │   │
│            │  YES: WebSocket ───────┼──→ Railway Server
│            │                        │   │  (FastAPI + GPT-4o
│            │  NO: On-device LLM ──┐ │   │   + Whisper + TTS)
│            └──────────────────────┼─┘   │
│                                   │     │
│  Answer ←── TTS ←── Text ←───────┘     │
│                                         │
│  Apple TTS (offline) / OpenAI TTS (online)
└─────────────────────────────────────────┘
```

### Online (Railway cloud)

- **STT**: OpenAI Whisper (server-side, tuned for legal terms)
- **LLM**: Falls through: OpenAI → Gemini → Groq → GitHub Models → local
- **RAG**: OpenAI Vector Stores with CA bar exam materials
- **TTS**: OpenAI TTS at ~80 WPM with section pauses

### Offline (on-device)

- **STT**: Apple SFSpeechRecognizer (built into iOS)
- **LLM**: SmolLM2-1.7B-Instruct via LLM.swift (llama.cpp)
- **RAG**: Baked-in legal knowledge (system prompt covers all CA bar subjects)
- **TTS**: Apple AVSpeechSynthesizer

The on-device model is smaller than GPT-4o. Answers are serviceable but less polished — it's "better than nothing" mode for flights, courthouses, and dead zones.

---

## Settings (Gear Icon)

| Setting | Default | Notes |
|---------|---------|-------|
| Speaking Speed | 0.55x (~80 WPM) | Slider from 0.5x to 2.0x |
| Voice | Nova (female) | 6 OpenAI voices available online |
| Silence Detection | 2.0s | How long to wait after you stop speaking |
| Mic Sensitivity | High | Picks up whisper-level speech |
| Wake Word | "hey bartender" | Customizable |
| Server URL | Railway URL | Pre-filled; change for local dev |
| Force Offline | Off | Toggle to use on-device model even with internet |

### Offline Mode section

- **Loaded** (green checkmark): Model is ready
- **Downloading** (progress bar): Model is downloading from HuggingFace (~1.1 GB)
- **Error** (red X): Tap "Retry Download" — needs WiFi for initial download

---

## Controls

### Bluetooth Clicker (Lock Screen)

| Button | Action |
|--------|--------|
| **Play** | Start recording |
| **Pause** | Stop recording / Pause TTS |
| **Next Track** | Repeat answer |
| **Previous Track** | Speed up |
| **Stop** | Cancel / Cycle mode (when idle) |

### Bluetooth Keyboard

| Key | Action |
|-----|--------|
| **Return** | Send question |
| **Escape** | Stop / Cancel |
| **Space** (unfocused) | Toggle mic |
| **Page Up/Down** | Speed ±0.1x |

### Apple Watch (optional)

Tap the record button on your wrist. The watch sends commands to the iPhone — it doesn't run the LLM itself. Requires WatchConnectivity and a paired Series 6+.

---

## Backend (Railway)

The server is deployed on Railway and auto-deploys on `git push`:

```bash
# Push backend changes
./launch.sh --server

# Or manually:
git push origin main
```

**Railway dashboard**: https://railway.app/project/48bcf658-2499-45c7-87a2-5844a63f032c

### API Keys

Create a `.env` file in the `bargrader/` directory:

```bash
# Required
OPENAI_API_KEY=sk-your-key-here

# Optional fallback providers
GEMINI_API_KEY=your-gemini-key
GROK_API_KEY=xai-your-key
GITHUB_TOKEN=ghp_your-pat

# OpenAI Vector Store IDs (for RAG)
OPENAI_VECTOR_ESSAY_EXEMPLARY=vs_...
OPENAI_VECTOR_SOURCE=vs_...
OPENAI_VECTOR_ESSAY_ATTACK=vs_...
```

Set these same variables in Railway → Variables for the deployed server.

### Local Development

```bash
pip install -r requirements-local.txt
./start_server.sh
```

Then change the Server URL in the app's Settings to `http://YOUR_MAC_IP:8080`.

---

## File Structure

```
bargrader/
├── launch.sh                # ← Run this. Builds & deploys everything.
├── backend/
│   ├── app.py               # FastAPI + WebSocket server
│   ├── config.py            # Settings, fallback chain config
│   ├── rag_engine.py        # OpenAI Vector Stores + ChromaDB
│   ├── llm_client.py        # Multi-provider LLM streaming
│   ├── prompts.py           # IRAC system prompt + mode detection
│   └── instructions/        # Essay / outline writing rules
├── ios/BarGrader/BarGrader/
│   ├── BarGraderApp.swift   # App entry + audio session
│   ├── Models/
│   │   └── AppState.swift   # Central state manager
│   ├── Views/
│   │   ├── ContentView.swift    # Main UI
│   │   └── SettingsView.swift   # Settings panel
│   └── Services/
│       ├── LocalLLMService.swift         # On-device LLM (LLM.swift)
│       ├── WebSocketService.swift        # Server connection
│       ├── AudioRecorderService.swift    # Mic + silence detection
│       ├── SpeechRecognitionService.swift # Apple STT
│       ├── TTSPlaybackService.swift      # Audio playback
│       ├── RemoteCommandService.swift    # BT / lock screen controls
│       └── WakeWordService.swift         # Wake word listener
├── frontend/                # PWA fallback (Safari)
├── tests/                   # pytest suite
├── requirements.txt         # Cloud dependencies
├── requirements-local.txt   # + local dev dependencies
├── nixpacks.toml            # Railway build config
└── railway.json             # Railway deploy config
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "No module named pip" on Railway | Already fixed in `nixpacks.toml`. Just `git push`. |
| Build fails with "no signing identity" | Xcode → Settings → Accounts → Add Apple ID |
| Build fails with "no provisioning profile" | Xcode → Target → Signing → Enable "Automatically manage signing" |
| iPhone not detected | USB cable + tap "Trust" on phone. Or same WiFi for wireless debugging. |
| App says "Disconnected" | Check Railway is running. Or toggle "Force Offline" in Settings. |
| Model download stuck | Needs WiFi. Tap "Retry Download" in Settings → Offline Mode. |
| Watch not syncing | iPhone and Watch must be paired. Open the iPhone app first. |
| `launch.sh` permission denied | `chmod +x launch.sh` |

---

## License

Personal use only. Study materials you add are your own.
