# Devpost Submission Package (Live Agents)

This document maps Arqivon artifacts to the Gemini Live Agent Challenge judging and submission requirements.

## 1) What to submit (required)

### Text Description
Use the sections already prepared in the project README:
- Problem
- Solution
- Four Specialized Agent Modes
- Google Cloud & Gemini Technologies Used
- How It Was Built
- Findings & Learnings

Reference: root README.

### Public Code Repository URL
- Repository: https://github.com/Medialordofficial/Arqivon
- Reproducibility: include the Spin-Up Instructions in README as-is.

### Proof of Google Cloud Deployment
Provide one of the following (recommended: both):
1. Short screen recording (30-60s) showing:
   - Cloud Run service page
   - latest revision
   - live logs while app is connected
2. Code proof links in repo:
   - backend/service.yaml
   - backend/Dockerfile
   - deploy.sh
   - app/lib/config/constants.dart

### Architecture Diagram
Use:
- architecture.png (primary upload)
- architecture.svg (high quality alternative)
- architecture.mmd (source)

### Demo Video (< 4 minutes)
Use:
- demo_storyboard.md
- docs/DEMO_VIDEO_SCRIPT_LIVE_AGENTS.md

## 2) Judging criteria alignment

### Innovation & Multimodal User Experience (40%)
Show in demo:
- Real-time voice + camera together in one continuous session
- Natural interruption (barge-in) while AI is speaking
- Mode switch mid-session with no restart friction
- Distinct mode behaviors (Assistant, Translator, Tutor, Support)

Evidence to call out:
- Live API native audio model for spoken interaction
- Dynamic UI overlays from tool calls in real time
- Session continuity and memory-backed context

### Technical Implementation & Agent Architecture (30%)
Show in demo + narrative:
- Google GenAI SDK live session lifecycle
- Cloud Run websocket backend architecture
- Firestore persistence (sessions, memories, artifacts)
- Tool dispatch pipeline and typed outbound events
- Reliability hardening (interrupt handling, watchdogs, reconnect)

Evidence to call out:
- 99 app tests passing
- backend model tests passing on Python 3.11
- successful release APK build
- stress checklist used for QA gate

### Demo & Presentation (30%)
Required in final video package:
- Clear problem statement in first 20-30s
- One coherent end-to-end user journey
- Real software footage only (no mockups)
- Visual architecture segment
- Measurable reliability claim backed by tests/checklist

## 3) Recommended 3-file upload set for judges

Upload these for fastest judge comprehension:
1. architecture.png
2. demo video (<4 min)
3. cloud proof clip (30-60s)

## 4) Reliability proof block (paste into Devpost description)

- Live interruption supported (barge-in) with immediate audio stop and turn re-focus
- Multimodal continuous stream (voice + camera) over bidirectional websocket
- Robust reconnect/session recovery paths for long-running conversations
- App tests: 99 passed
- Backend tests (Python 3.11): passing
- Release build validated
- Manual stress protocol: QA_LIVE_CONVERSATION_STRESS_CHECKLIST.md

## 5) Final pre-submit gate

Submit only when all are true:
- No stuck Listening/Responding states in stress run
- No silent-audio-with-transcript regressions
- Interruption works repeatedly in same session
- Cloud proof clip recorded and attached
- Demo video under 4 minutes and includes real multimodal flow
