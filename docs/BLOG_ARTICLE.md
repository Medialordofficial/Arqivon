# Building a Real-Time Multimodal AI Voice Agent with Gemini Live API + Flutter

*How we built Arqivon — a 4-mode AI assistant that sees your camera, hears your voice, and acts through 17 agentic tools, all powered by Gemini's native audio and the Google GenAI SDK.*

---

## The Pain Point Nobody Talks About

Every AI assistant today works the same way: you type, it responds. Maybe you can speak to it, but then you wait. Then it speaks back. Turn by turn, like a chess game.

But life isn't turn-based.

You're holding groceries, standing in front of a foreign menu. You're staring at a calculus problem on a whiteboard with both hands full of textbooks. You're troubleshooting a broken router while on the phone with support. In all these scenarios, you need an AI that can **see what you see** and **hear what you say** — simultaneously, in real time, and respond with **actual voice** while showing you **actionable UI**.

That's why we built **Arqivon**.

---

## What We Built

Arqivon is a Flutter mobile app backed by a FastAPI WebSocket relay, speaking to the **Gemini Live API** (`gemini-2.5-flash-native-audio-latest`). It captures your camera at 2fps and your microphone at 16kHz PCM, streams both to Gemini simultaneously, and renders the AI's responses as native audio + mode-specific UI overlays.

It has four specialized agent modes:

| Mode | What It Does |
|------|-------------|
| **Assistant** | General multimodal helper — creates Smart Action Cards from what it sees |
| **Translator** | Real-time translation overlay for 100+ languages with exportable PDFs |
| **Tutor** | Vision-enabled tutor that solves homework step-by-step from your camera feed |
| **Support** | Customer support agent with topic tracking, case escalation, and resolution logs |

Each mode has its own system prompt, personality, and dedicated subset of 17 agentic tools. When you switch modes mid-conversation, the backend tears down the Gemini session and rebuilds it with a new tool registry — no disconnect for the user.

---

## The Architecture: WebSocket Relay Pattern

Here's the key insight that shaped our architecture: **the Gemini Live API is a server-to-server API**. You can't call it directly from a mobile app. You need a relay.

```
Flutter App ←→ WebSocket ←→ FastAPI (Cloud Run) ←→ Gemini Live API
```

### Why a Relay?

1. **API key security** — The Gemini API key lives in Google Secret Manager, injected into Cloud Run. The Flutter app never touches it.
2. **Tool dispatch** — When Gemini calls a function (e.g., `live_translate`, `solve_problem`), the backend executes it, writes to Firestore, and routes the result back to both Gemini and the client.
3. **Session management** — Each WebSocket connection gets its own Gemini Live session. The backend tracks mode, language preferences, voice selection, and conversation history per user.

### The WebSocket Message Protocol

We defined a clean bidirectional protocol:

**Client → Server:**
```json
{"type": "audio", "data": "<base64 PCM>"}
{"type": "video", "data": "<base64 JPEG>"}
{"type": "set_mode", "mode": "translator", "voice": "Aoede"}
{"type": "set_language", "source_lang": "ja", "target_lang": "en"}
{"type": "text", "text": "What's this equation?"}
```

**Server → Client:**
```json
{"type": "audio", "data": "<base64 PCM>"}
{"type": "transcript", "text": "The equation is..."}
{"type": "user_transcript", "text": "What's this?"}
{"type": "translation", "payload": {"source_text": "...", "translated_text": "..."}}
{"type": "tutor_step", "payload": {"tool": "solve_problem", "steps": [...]}}
{"type": "turn_complete"}
{"type": "interrupted"}
```

---

## Deep Dive: Connecting to Gemini Live API

The core connection code uses the `google-genai` Python SDK's async live streaming:

```python
from google import genai
from google.genai import types

client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])

config = types.LiveConnectConfig(
    response_modalities=["AUDIO"],
    speech_config=types.SpeechConfig(
        voice_config=types.VoiceConfig(
            prebuilt_voice_config=types.PrebuiltVoiceConfig(
                voice_name="Aoede"
            )
        )
    ),
    system_instruction=types.Content(
        parts=[types.Part(text=system_prompt)]
    ),
    tools=tool_declarations,  # Mode-specific function declarations
    automatic_activity_detection=types.AutomaticActivityDetection(
        disabled=False,
        start_of_speech_sensitivity=types.StartSensitivity.START_SENSITIVITY_HIGH,
        end_of_speech_sensitivity=types.EndSensitivity.END_SENSITIVITY_HIGH,
    ),
    input_audio_transcription=types.AudioTranscriptionConfig(),
    output_audio_transcription=types.AudioTranscriptionConfig(),
)

async with client.aio.live.connect(model="gemini-2.5-flash-native-audio-latest", config=config) as session:
    # Now bidirectionally stream audio + video
    ...
```

### Key Learnings

**1. Native audio output is transformative.** Unlike text-to-speech, Gemini's native audio model generates speech with natural prosody, emphasis, and pacing. It sounds like a real person, not a robot reading text. The key is `response_modalities=["AUDIO"]`.

**2. VAD sensitivity matters enormously.** We set both `start_of_speech_sensitivity` and `end_of_speech_sensitivity` to `HIGH`. This means Gemini detects when you start speaking almost instantly (enabling barge-in — you can interrupt the AI mid-sentence) and also stops listening quickly after you pause, reducing awkward silence.

**3. Tool declarations per mode are essential.** Don't give the model 17 tools in every mode. Our Translator mode only sees 4 tools; Tutor sees 7; Support sees 5. This keeps responses focused and prevents tool confusion.

**4. `send_realtime_input()` vs `send_client_content()`.** Use `send_realtime_input()` for streaming audio and video frames — it's fire-and-forget, non-blocking. Use `send_client_content()` for text messages that need to be processed as part of the conversation context.

---

## Barge-In: The Feature That Makes It Feel Real

Barge-in is when the user interrupts the AI while it's speaking. This is the single most important feature for making a voice agent feel natural. Without it, you're stuck waiting for the AI to finish before you can redirect it.

Here's how barge-in works end-to-end:

1. **Mic stays active during playback.** The Flutter `AudioService` runs the microphone recorder and the audio player independently. The mic never stops.

2. **Gemini's native VAD detects interruption.** With `AutomaticActivityDetection` set to `HIGH`, Gemini's server-side voice activity detection knows when the user starts speaking.

3. **`interrupted` signal fires.** The Gemini Live session sends an `interrupted` event through the response stream.

4. **Backend relays it.** Our FastAPI relay forwards `{"type": "interrupted"}` to the Flutter client.

5. **Client stops playback instantly.** The `LiveSessionNotifier` calls `AudioService.stopPlayback()`, which kills the audio player, clears the PCM buffer, and removes any stale UI overlays.

```dart
case 'interrupted':
  _audio?.stopPlayback();
  state = AsyncData(current.copyWith(
    isResponding: false,
    clearTranslation: true,
    clearAction: true,
    clearTutorStep: true,
    clearExport: true,
  ));
```

The result: you can say "Wait, that's wrong" in the middle of the AI's explanation, and it immediately stops and re-engages. It feels like talking to a real person.

---

## Vision: Sending Camera Frames to Gemini

The Gemini Live API accepts inline image data as part of the real-time stream. We capture JPEG frames from the device camera at 2fps and send them alongside the audio:

```dart
// Flutter: Capture camera frame
Timer.periodic(const Duration(milliseconds: 500), (_) async {
  final image = await cameraController.takePicture();
  final bytes = await image.readAsBytes();
  final b64 = base64Encode(bytes);
  notifier.sendVideoFrame(b64);
});
```

```python
# Backend: Forward to Gemini
frame_bytes = base64.b64decode(b64_frame)
await session.send_realtime_input(
    media=types.Blob(data=frame_bytes, mime_type="image/jpeg")
)
```

Gemini processes the image in context with the ongoing audio conversation. So when you point your camera at a math problem and say "Can you solve this?", the model already has the image and knows exactly what "this" refers to.

### Frame Failure Resilience

Camera capture can fail (low memory, app backgrounding, permissions). We track consecutive failures and stop frame capture after 10 failures in a row to prevent wasted resources:

```dart
if (consecutiveFailures >= 10) {
  frameTimer?.cancel();
  log.warning('Frame capture stopped after 10 consecutive failures');
}
```

---

## 17 Agentic Tools: Real Function Calling

Every tool is a real Python function that returns structured JSON. No mocks, no stubs. Here's an example — the `live_translate` tool:

```python
async def live_translate(
    source_text: str,
    translated_text: str,
    source_language: str = "auto",
    target_language: str = "en",
    formality: str = "neutral",
    **_,
) -> dict:
    return {
        "source_text": source_text,
        "translated_text": translated_text,
        "source_language": source_language,
        "target_language": target_language,
        "formality": formality,
        "status": "translated",
    }
```

When Gemini calls this tool, the backend:

1. Dispatches to the handler via `dispatch_tool_call()`
2. Sends the result back to Gemini via `send_tool_response()`
3. Routes a `TRANSLATION` message to the Flutter client
4. The client renders a `TranslationOverlay` widget with source and translated text

Some tools write to Firestore (memories, session records, exported documents). Others trigger client-side UI (action cards, tutor steps, translation overlays). The routing layer inspects the tool name and sends the appropriate outbound message type.

---

## The Audio Pipeline: Harder Than It Looks

Building reliable real-time audio on mobile is where most of our debugging time went. Here's what we learned:

### Recording (Mic → WebSocket)

We use the `record` package for Flutter with PCM-16 at 16kHz mono. The raw PCM chunks are base64-encoded and sent over the WebSocket:

```dart
final stream = await recorder.startStream(RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
  echoCancel: true,
  noiseSuppress: true,
  autoGain: true,
));
```

### Playback (WebSocket → Speaker)

Gemini sends back PCM-16 at 24kHz. We can't just pipe raw PCM to the speaker — the `just_audio` package needs WAV files. So we buffer incoming PCM chunks, flush them periodically into temporary WAV files with proper RIFF headers, and add them to a `ConcatenatingAudioSource` playlist:

```dart
Uint8List _buildWav(Uint8List pcm, {int sampleRate = 24000}) {
  final header = ByteData(44);
  // Write RIFF header...
  // Write fmt sub-chunk (PCM format, mono, 24kHz, 16-bit)...
  // Write data sub-chunk...
  final wav = Uint8List(44 + pcm.length);
  wav.setRange(0, 44, header.buffer.asUint8List());
  wav.setRange(44, 44 + pcm.length, pcm);
  return wav;
}
```

### The Android Audio Focus Problem

On Android, when the audio player starts (AI speaking), the system can silently kill the microphone recorder without firing any callbacks. The `_isCapturing` flag stays `true`, but the platform stream is dead. No `onDone`, no `onError` — just silence.

The fix: after every AI turn completes, force-restart the recorder regardless of its reported state:

```dart
Future<void> ensureRecording() async {
  _isCapturing = false;
  _recordSub?.cancel();
  await _recorder.stop();
  await start();  // Fresh stream, guaranteed alive
}
```

This single function eliminated our most frustrating bug.

---

## Audio-Reactive Orb Visualizer

The UI centerpiece is a glowing orb that reacts to the user's voice amplitude. We compute RMS (root mean square) amplitude from the raw PCM recording data and pipe it through a `ValueNotifier` to the `CustomPainter`:

```dart
void _emitAmplitude(Uint8List pcm) {
  final sampleCount = pcm.length ~/ 2;
  double sumSquares = 0;
  for (var i = 0; i < sampleCount; i++) {
    int sample = pcm[i * 2] | (pcm[i * 2 + 1] << 8);
    if (sample >= 0x8000) sample -= 0x10000;
    sumSquares += sample * sample;
  }
  final rms = sumSquares / sampleCount;
  final normalized = ((rms / (32767.0 * 32767.0)) * 4.0).clamp(0.0, 1.0);
  amplitudeController.add(normalized);
}
```

The orb itself is painted with layered radial gradients (cyan → blue → indigo → purple → deep edge), a specular highlight, rim glow, and three staggered ripple rings. The amplitude modulates the orb radius and outer glow intensity:

```dart
final orbR = baseR * (1.0 + 0.04 * active + 0.10 * amplitude * active);
```

---

## Persistent Memory: The Firestore Layer

One feature that truly differentiates a voice agent is **memory**. Our `upsert_firestore_memory` tool lets Gemini store facts about the user:

```python
async def upsert_firestore_memory(key: str, value: str, **kwargs) -> dict:
    user_id = kwargs.get("user_id", "")
    mem_ref = db.collection("users").document(user_id) \
                .collection("memories").document(key)
    mem_ref.set({
        "key": key, "value": value,
        "updated_at": firestore.SERVER_TIMESTAMP
    }, merge=True)
    return {"status": "stored", "key": key}
```

After a few conversations, Gemini learns your name, preferred language, topics of interest, and common questions. We built a Memories viewer screen so users can see (and delete) what the AI remembers.

Session summaries are generated using `gemini-2.0-flash-lite` at session teardown — the backend sends the last 50 transcript utterances and gets back a concise summary that's saved to Firestore.

---

## Deployment on Google Cloud

Our production stack:

| Service | Purpose |
|---------|---------|
| **Cloud Run** | FastAPI backend, min 1 instance (no cold starts), 1hr WebSocket timeout, CPU always-on |
| **Secret Manager** | `GEMINI_API_KEY` injection |
| **Artifact Registry** | Docker image storage |
| **Firebase Hosting** | Landing page + Privacy Policy + Terms of Service |
| **Firestore** | User data, sessions, memories, exports (with strict `uid`-based security rules) |
| **Firebase Auth** | Google Sign-In + Apple Sign-In + Email/Password |
| **Cloud Storage for Firebase** | Exported documents (translations, solutions, support notes) stored for download |
| **Firebase Cloud Messaging (FCM)** | Push notifications when sessions are saved with AI-generated summaries |
| **Firebase Crashlytics** | Crash reporting and error monitoring in production |

### Firebase Cloud Messaging

When a session ends, the backend generates an AI summary and saves it to Firestore. It then sends a push notification to the user's device via FCM:

```python
message = fb_messaging.Message(
    notification=fb_messaging.Notification(
        title=f"💾 {session_title}",
        body=ai_summary[:200],
    ),
    data={"session_id": session_id, "mode": mode},
    token=fcm_token,  # Retrieved from user's Firestore doc
)
await asyncio.to_thread(fb_messaging.send, message)
```

On the Flutter side, we request notification permissions at startup, save the FCM device token to the user's Firestore document, and listen for token refreshes:

```dart
final messaging = FirebaseMessaging.instance;
await messaging.requestPermission(alert: true, badge: true, sound: true);
final token = await messaging.getToken();
// Save to Firestore: users/{uid}/fcmToken
```

### Cloud Storage for Firebase

Exported documents (translated texts, solved problems, support notes) are uploaded to Cloud Storage, giving users persistent download URLs they can access later from the Archive screen:

```python
bucket = fb_storage.bucket()
blob = bucket.blob(f"exports/{user_id}/{timestamp}_{title}.txt")
await asyncio.to_thread(blob.upload_from_string, content)
await asyncio.to_thread(blob.make_public)
download_url = blob.public_url
```

We automated deployment with a GitHub Actions workflow that runs tests, builds the Docker image, pushes to Artifact Registry, deploys to Cloud Run, and verifies the health endpoint — all triggered on push to `main`.

---

## Numbers

- **~10,600 lines** of code across 44 source files
- **17 agentic tools** across 4 agent modes
- **99 unit tests** passing (7 Flutter test files + 1 Python test file)
- **9 selectable AI voices** (Aoede, Charon, Fenrir, Kore, Puck, and more)
- **2fps camera** + **16kHz mic** streaming simultaneously
- **5-attempt reconnect** with exponential backoff on both WebSocket and Gemini sessions
- **~250ms flush interval** for audio playback buffering
- **12-second heartbeat** on WebSocket connections

---

## What I'd Do Differently

1. **Start with ADK.** The Agent Development Kit would have given us session management, built-in tool orchestration, and better observability for free. We built all of it manually.

2. **Add Search grounding early.** Gemini's Search grounding tool would let the agent answer questions about real-time information (weather, news, prices) without hallucinating. We didn't integrate it and that's a gap.

3. **Test the audio pipeline on Day 1.** We lost more time to platform-specific audio bugs (Android audio focus, PCM buffering, WAV header construction) than any other feature combined. If I were starting over, I'd build the audio round-trip first and everything else second.

4. **Don't suppress output transcription.** We initially disabled `output_audio_transcription` because it sometimes produced text in unexpected languages. Turns out, users really want to see what the AI said as text, especially during a demo. We re-enabled it and the experience improved dramatically.

---

## Try It

The full source code is on GitHub: [Arqivon](https://github.com/your-repo/arqivon)

The live backend runs at Cloud Run. The landing page is at [arqivon-inc.web.app](https://arqivon-inc.web.app).

If you're building with the Gemini Live API, I hope this saves you some of the debugging time we spent. The API is genuinely powerful — once you get the audio pipeline working, everything else clicks.

---

*Built for the [Gemini Live Agent Challenge](https://geminiliveagentchallenge.devpost.com). #GeminiLiveAgentChallenge #GeminiAPI #Flutter #GoogleCloud*
