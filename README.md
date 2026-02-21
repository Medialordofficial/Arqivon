# Arqivon – The Living Lens

> **A real-time, multimodal Live Agent that sees what you see, hears what you hear, and acts before you ask.**

---

## What It Does

Arqivon transforms your phone into an intelligent "Living Lens." Point your camera at anything — a business card, a menu in another language, a math problem on a whiteboard — and Arqivon **simultaneously** processes your **live video feed** and **continuous voice** through the Gemini Live API. It doesn't just describe what it sees; it **takes action**.

### Four Specialized Modes

| Mode | Icon | What It Does |
|------|------|-------------|
| **Assistant** | ✨ | Proactive multimodal assistant — detects actionable items in your camera feed and creates Smart Action Cards |
| **Translator** | 🌐 | Real-time multilingual translator — speak in one language, hear/see translation on the fly with graceful interruptions |
| **Tutor** | 🎓 | Vision-enabled smart tutor — show homework or diagrams via camera, get step-by-step guidance with progress tracking |
| **Support** | 🎧 | Voice-driven customer support agent — natural call-like interaction with mid-conversation topic switching and session history |

### Core Principles

- **Natural, uninterrupted conversation:** Native VAD means you can interrupt mid-sentence and the agent instantly re-focuses
- **Multimodal input:** Simultaneous 2fps JPEG frames + 16kHz PCM audio over a single WebSocket
- **Contextual intelligence:** Persistent memory across sessions, mode-specific tool calling, context-aware responses
- **Global usability:** 19 languages supported in translator mode, accessible UI across all modes

### Key Differentiators

- **Simultaneous Vision + Voice:** 2fps JPEG frames and 16kHz PCM audio stream concurrently over a single WebSocket
- **Zero-latency Interruptibility:** Native VAD means you can interrupt mid-sentence and the agent instantly re-focuses
- **Mode-Aware Agentic Tools:** 13 registered tools across 4 mode categories, with mode-specific system prompts and tool declarations
- **Persistent Memory:** "Remember that I'm allergic to peanuts" → stored permanently in Firestore, recalled in future sessions
- **Beautiful Glassmorphism UI:** Frosted-glass cards, animated audio waveforms, mode-colored accents, seamless dark/light mode

---

## Use Cases

### 1. Real-Time Multilingual Translator
Speak naturally in one language and hear the AI translate your words on the fly. A live translation overlay shows source text, target language, and formality level. Supports graceful interruptions — change what you're saying mid-sentence and the translator adapts instantly.

### 2. Vision-Enabled Smart Tutor
Point your camera at homework, diagrams, or textbook problems. The tutor analyzes what it sees, breaks down solutions into numbered steps with progress bars, provides hints on demand, and grades each step with detailed feedback. Concepts are tagged for future reference.

### 3. Voice-Driven Customer Support Agent
A natural call-like support experience. Describe your issue verbally and the agent tracks conversation topics in real-time. Switch topics mid-conversation seamlessly. The agent can escalate cases, log resolutions, and maintain full session history for follow-up.

---

## Architecture

```
┌──────────────────┐    WebSocket (bidir)     ┌─────────────────────┐
│   Flutter App    │ ◄───────────────────────► │  FastAPI on         │
│   (Riverpod)     │  audio PCM + JPEG →      │  Cloud Run          │
│                  │  ← audio + actions +      │                     │
│  ┌────────────┐  │    translations + steps   │  ┌───────────────┐  │
│  │ Mode       │  │                           │  │ Mode-Aware    │  │
│  │ Selector   │  │                           │  │ System Prompts│  │
│  ├────────────┤  │                           │  ├───────────────┤  │
│  │ Camera 2fps│  │                           │  │ Tool Registry │  │
│  ├────────────┤  │                           │  │ (13 tools)    │  │
│  │ Mic / VAD  │  │                           │  ├───────────────┤  │
│  ├────────────┤  │                           │  │ Gemini Live   │  │
│  │ Mode-      │  │                           │  │ Session       │  │
│  │ Specific   │  │                           │  │ (per-user)    │  │
│  │ Overlays   │  │                           │  ├───────────────┤  │
│  └────────────┘  │                           │  │ Firestore     │  │
└────────┬─────────┘                           └───────┬───────────┘
         │         Firebase Auth / Firestore           │
         └─────────────────────────────────────────────┘
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| AI Brain | `gemini-2.0-flash-live-001` via Google GenAI SDK |
| Backend | FastAPI + WebSockets, containerized on **Google Cloud Run** |
| Frontend | Flutter 3.x + **Riverpod** `AsyncNotifier` |
| Auth | **Firebase Auth** (Google Sign-In) |
| Database | **Cloud Firestore** (sessions, memories, translations, support topics) |
| Storage | **Google Cloud Storage** (media caching) |
| Transport | Bidirectional WebSockets with heartbeat + exponential backoff |

### Tool Registry (13 Tools)

| Category | Tools | Purpose |
|----------|-------|---------|
| **Shared** | `analyze_live_frame`, `upsert_firestore_memory`, `create_ui_action` | Common vision analysis, persistent memory, UI actions |
| **Translator** | `live_translate`, `detect_language`, `translation_card` | Real-time translation, language detection, translation UI |
| **Tutor** | `analyze_homework`, `provide_hint`, `grade_step`, `tutor_card` | Homework analysis, step-by-step hints, grading, tutor UI |
| **Support** | `switch_topic`, `escalate_case`, `log_resolution`, `support_card` | Topic management, escalation, resolution logging, support UI |

---

## Project Structure

```
Arqivo/
├── backend/
│   ├── main.py               # FastAPI WS relay + mode-aware Gemini sessions
│   ├── config.py              # Environment-based settings
│   ├── models.py              # Pydantic schemas (AgentMode, message types)
│   ├── tool_registry.py       # 13 agentic tools across 4 mode categories
│   ├── requirements.txt
│   ├── Dockerfile             # Multi-stage, Cloud Run optimized
│   ├── service.yaml           # Cloud Run knative config (min-instances: 1)
│   └── .env.example
├── app/
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart
│       ├── config/
│       │   ├── constants.dart
│       │   └── theme.dart          # Glassmorphism dark/light themes
│       ├── models/
│       │   ├── agent_mode.dart     # AgentMode enum + TutorStep/Translation/SupportTopic
│       │   ├── ws_message.dart     # WebSocket message types (mode-aware)
│       │   ├── smart_action.dart   # Smart Action Card model
│       │   └── session_model.dart  # Archive session model (mode + topics)
│       ├── services/
│       │   ├── websocket_service.dart  # Production WS with backoff
│       │   ├── audio_service.dart      # Mic capture + playback
│       │   ├── auth_service.dart       # Firebase Auth + Google Sign-In
│       │   └── firestore_service.dart  # Sessions & memories CRUD
│       ├── providers/
│       │   ├── auth_provider.dart
│       │   ├── settings_provider.dart  # Theme + voice + mode + language persistence
│       │   ├── live_session_provider.dart  # Mode-aware AsyncNotifier
│       │   └── session_provider.dart      # Archive list
│       ├── widgets/
│       │   ├── glassmorphic_card.dart
│       │   ├── smart_action_card.dart      # Expandable action cards
│       │   ├── session_tile.dart           # Mode-colored archive tiles
│       │   ├── audio_visualizer.dart       # Animated waveform
│       │   ├── connection_indicator.dart
│       │   ├── mode_selector.dart          # Horizontal mode picker strip
│       │   ├── translation_overlay.dart    # Live translation subtitle card
│       │   ├── tutor_guidance_card.dart    # Step-by-step tutor card
│       │   └── support_topic_tracker.dart  # Topic trail tracker
│       └── screens/
│           ├── live_screen.dart     # Camera + audio + mode overlays
│           ├── home_screen.dart     # Archive with mode filter chips
│           └── settings_screen.dart # Theme, voice, mode, language
├── firebase/
│   ├── firebase.json
│   ├── firestore.rules         # Strict uid-based data isolation
│   ├── firestore.indexes.json
│   └── storage.rules
├── architecture.mmd            # Mermaid diagram source
├── demo_storyboard.md          # <4 min video script
└── README.md
```

---

## Local Setup

### Prerequisites

- Flutter 3.x SDK
- Python 3.11+
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey)
- Firebase project with Auth + Firestore enabled

### Backend

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in your GEMINI_API_KEY
uvicorn main:app --reload --port 8080
```

Verify: `curl http://localhost:8080/health`

### Flutter App

```bash
cd app
flutter pub get
# Configure Firebase:
#   flutterfire configure
# Then uncomment Firebase.initializeApp() in main.dart
flutter run
```

---

## Google Cloud Deployment

### 1. Build & Push

```bash
cd backend
gcloud builds submit --tag gcr.io/$PROJECT_ID/arqivon-backend
```

### 2. Deploy to Cloud Run

```bash
gcloud run deploy arqivon-backend \
  --image gcr.io/$PROJECT_ID/arqivon-backend \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --min-instances 1 \
  --timeout 3600 \
  --cpu-no-throttle \
  --set-env-vars="GEMINI_API_KEY=$(gcloud secrets versions access latest --secret=GEMINI_API_KEY)"
```

### 3. Update Flutter WebSocket URL

In `app/lib/config/constants.dart`, update `wsHost` to your Cloud Run service URL.

---

## How It Was Built

1. **Mode-aware backend:** FastAPI manages per-user WebSocket connections, each spawning a Gemini Live API session with mode-specific system prompts and tool declarations. Three concurrent coroutines handle client→Gemini, Gemini→client, and heartbeat. Mode/language switching triggers live Gemini session reconnection.

2. **Tool Registry:** `tool_registry.py` declares 13 `FunctionDeclaration` objects across 4 categories. When Gemini invokes a tool, the backend dispatcher routes it to the correct handler, converts results to typed outbound messages (TRANSLATION, TUTOR_STEP, SUPPORT_TOPIC, UI_ACTION), and sends tool results back to Gemini.

3. **Flutter state:** `LiveSessionNotifier` (Riverpod `AutoDisposeAsyncNotifier`) owns the full lifecycle: connect → set mode → stream audio/video → receive mode-specific responses → render overlay widgets → persist session on disconnect.

4. **Mode-specific UI:** Each mode gets its own overlay: TranslationOverlayWidget (source→target with formality), TutorGuidanceCard (progress bars, hints, grading), SupportTopicTracker (topic trail with reasons). The ModeSelectorStrip enables instant mode switching during a session.

5. **Reconnection:** Both WebSocket service (Flutter) and Gemini connector (backend) implement exponential backoff with jitter, capped at 30s / 5 attempts.

---

## Judging Criteria Coverage

| Category (Weight) | What We Built |
|---|---|
| **Cloud Architecture** (30%) | Cloud Run + min-instances, multi-stage Dockerfile, Firestore rules, GCS, Firebase Auth, mode-aware session management |
| **Innovation & UX** (40%) | 4 specialized modes, simultaneous vision+voice, Smart Action Cards, glassmorphism UI, VAD interruptibility, persistent memory, 13 agentic tools, live translation overlay, step-by-step tutoring |
| **Demo & Presentation** (30%) | Architecture diagram, 4-min demo storyboard, scene-by-scene script covering all 3 use-cases |

---

## License

MIT
