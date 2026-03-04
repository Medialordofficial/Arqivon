# Demo Video Script (Live Agents Category, < 4 min)

Use this as a direct narration + shot list for the final Devpost demo.

## Duration target
- 3:20 to 3:50 total

## Segment 1 — Problem + Hook (0:00-0:25)

Visual:
- Open Arqivon on phone
- Start live mode quickly

Narration:
- "Most AI assistants are still text-box tools. Real life is voice and vision together."
- "Arqivon is a real-time Live Agent that sees what you see, hears what you hear, and responds instantly."

## Segment 2 — Core Live Interaction (0:25-1:20)

Visual:
- Show camera at a real object/sign/document
- Speak naturally to ask for understanding/translation
- Let AI start speaking
- Interrupt AI mid-sentence with a correction or new question

Narration points:
- "This is one continuous multimodal stream: live camera plus live voice."
- "Notice interruption: the assistant stops immediately, listens, and pivots to new context without getting lost."

Must-capture outcome:
- Audible interruption handling
- Correct follow-up response tied to interruption

## Segment 3 — Agentic Actions (1:20-2:10)

Visual:
- Ask to save a note
- Ask to set a reminder
- Show UI confirmation cards appearing in real time

Narration points:
- "Arqivon is not just chat. It calls tools and takes actions in-session."
- "Tool results are rendered as typed UI events on the device."

## Segment 4 — Mode Switching in Live Session (2:10-2:50)

Visual:
- Switch from Assistant to Translator or Tutor
- Ask a mode-specific question immediately
- Show mode-specific overlay/response

Narration points:
- "Each mode has dedicated prompts and tool access."
- "Switching modes keeps the conversation live and context-aware."

## Segment 5 — Architecture + Reliability (2:50-3:30)

Visual:
- Show architecture.png briefly
- Show quick terminal snippet or test summary screenshot

Narration points:
- "Backend runs on Google Cloud Run with Gemini Live API via Google GenAI SDK."
- "State and memory persist in Firestore."
- "We validated reliability with automated tests, release builds, and stress checks focused on barge-in and long-session continuity."

## Segment 6 — Closing (3:30-3:45)

Narration:
- "Arqivon turns AI from turn-based chat into seamless live collaboration."
- "That is why we built it for the Gemini Live Agent Challenge."

## Separate required clip (not part of 4-min demo)

Record a 30-60 second proof-of-cloud clip:
- Cloud Run service page
- active revision
- live logs while app is connected
- optional: point to service.yaml and deploy.sh in repo
