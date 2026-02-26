# Arqivon Demo Video — Production Guide

> **Goal:** A 3:50 video that wins the Gemini Live Agent Challenge.
> **Upload to:** YouTube (public, not unlisted) → paste link into Devpost submission.

---

## Table of Contents

1. [Winning Strategy](#1-winning-strategy)
2. [Equipment & Software](#2-equipment--software)
3. [Pre-Production Checklist](#3-pre-production-checklist)
4. [Complete Shot List & Script](#4-complete-shot-list--script)
5. [Recording Instructions](#5-recording-instructions)
6. [Editing Instructions](#6-editing-instructions)
7. [Upload & Submission](#7-upload--submission)
8. [Common Mistakes to Avoid](#8-common-mistakes-to-avoid)

---

## 1. Winning Strategy

### What Judges Score (from the rules)

| Criterion | Weight | What They Want to See |
|-----------|--------|----------------------|
| **Innovation & Multimodal UX** | **40%** | Beyond-text interaction, seamless see/hear/speak, barge-in, distinct persona |
| **Technical Implementation** | **30%** | Google Cloud native, GenAI SDK, robust error handling, no hallucinations |
| **Demo & Presentation** | **30%** | Clear problem/solution story, architecture proof, actual working software |

### Video Structure That Maximizes Score

```
0:00 - 0:25  → HOOK: The problem + solution pitch (Demo & Presentation)
0:25 - 1:10  → LIVE DEMO: Assistant Mode + barge-in (Innovation 40%)
1:10 - 1:55  → LIVE DEMO: Translator Mode with camera (Innovation 40%)
1:55 - 2:40  → LIVE DEMO: Tutor Mode solving math (Innovation 40%)
2:40 - 3:05  → LIVE DEMO: Support Mode + PDF export (Innovation 40%)
3:05 - 3:30  → ARCHITECTURE: Diagram + Cloud Run proof (Technical 30%)
3:30 - 3:50  → CLOSE: Recap + call to action (Demo & Presentation 30%)
```

### The Golden Rule
**Every second must show REAL SOFTWARE WORKING.** No slides with bullet points. No mockups. The judges explicitly say "show the actual software." Your phone screen IS the presentation.

---

## 2. Equipment & Software

### Minimum Setup (What You Have)
- [ ] **MacBook Air** — for screen recording the phone via QuickTime
- [ ] **iPhone/Android** — running Arqivon with stable internet
- [ ] **Lightning/USB-C cable** — to mirror phone to Mac
- [ ] **Quiet room** — background noise kills voice assistant demos
- [ ] **Good lighting** — so camera mode footage is clear

### Recording Software
- **QuickTime Player** (free, macOS) — `File → New Movie Recording → select iPhone`
- **OBS Studio** (free) — if you want picture-in-picture with your face
- **ScreenFlow** ($) — best option if you already own it

### Editing Software (pick one)
- **iMovie** (free, macOS) — sufficient for this
- **DaVinci Resolve** (free) — more control, color grading
- **CapCut** (free) — fast, good text animations

### Audio
- **AirPods / wired earbuds with mic** — wear ONE earbud so AI audio plays through speaker for recording
- OR record phone audio separately and sync in post

### Props for Camera Demos
- [ ] A menu or sign in a foreign language (Spanish/French/Japanese) — for Translator mode
- [ ] A math problem written on paper or whiteboard — for Tutor mode
- [ ] A printed business card or document — for Assistant mode
- [ ] Your laptop showing the GCP Console — for deployment proof

---

## 3. Pre-Production Checklist

### The Day Before Recording

- [ ] **Test the app end-to-end** — all 4 modes working, backend responding
- [ ] **Verify Cloud Run** is running: `curl https://arqivon-backend-653546103163.us-central1.run.app/health`
- [ ] **Charge your phone** to 100%
- [ ] **Enable Do Not Disturb** on both phone and Mac
- [ ] **Close all other apps** — you need clean RAM for smooth recording
- [ ] **Prepare physical props:**
  - Print a restaurant menu in Spanish or French
  - Write a calculus or algebra problem on paper: e.g. ∫(3x² + 2x)dx
  - Have a business card or document ready
- [ ] **Set phone brightness to 80%+** for clear screen recording
- [ ] **Practice the script out loud** at least 3 times
- [ ] **Time yourself** — aim for 3:30 raw, editing will add ~20s of transitions

### Right Before Recording

- [ ] Plug phone into Mac, open QuickTime → New Movie Recording → select phone
- [ ] Open Arqivon, sign in, verify connection indicator is green
- [ ] Make sure AI voice is set to your preferred voice in Settings
- [ ] Set mode to "Assistant" (starting mode)
- [ ] Clear any previous sessions from archive (clean slate)
- [ ] Position your camera props within arm's reach
- [ ] Start QuickTime recording
- [ ] Take a deep breath, wait 3 seconds of silence, then begin

---

## 4. Complete Shot List & Script

### SCENE 1: THE HOOK (0:00 – 0:25) — 25 seconds

**What's on screen:** Quick montage — you holding phone, pointing camera at various things, AI responding in real-time. Use fast cuts (1-2 sec each) from footage you'll record in the demo sections.

> **YOUR VOICEOVER (add in editing):**
>
> "What if your AI assistant could see what you see, hear what you hear, and act before you even finish asking? Current AI is trapped behind a text box. But real life is multimodal. Meet Arqivon — a real-time Live Agent powered by Gemini 2.5 Flash that transforms your phone into an intelligent Living Lens."

**Editing note:** Record this voiceover separately in a quiet room. Overlay it on top of the montage clips. This is the ONLY part that's narration — everything else is live.

---

### SCENE 2: ASSISTANT MODE + BARGE-IN (0:25 – 1:10) — 45 seconds

**What's on screen:** Phone screen recording showing Arqivon in Assistant mode.

**Setup:** Point camera at your desk/surroundings.

| Timestamp | You Say | Arqivon Does | What Judges See |
|-----------|---------|-------------|-----------------|
| 0:25 | Tap the mic button to start a session | Connection indicator turns green, orb animates | Live API connection |
| 0:28 | "Hey, what can you see right now?" | AI describes what camera sees in real-time | **Multimodal: Vision + Voice** |
| 0:35 | Point camera at a business card or document | AI reads it: "I see a business card for..." | **Camera + AI analysis** |
| 0:40 | "Can you remember that contact for me?" | Smart Action Card appears, memory saved to Firestore | **Agentic tool: upsert_memory** |
| 0:47 | **INTERRUPT mid-sentence:** "Wait, what color is it?" | AI stops immediately, answers new question | **BARGE-IN (critical for Live Agents)** |
| 0:55 | "Actually, create an action for that" | UI Action card slides in with glassmorphic effect | **Agentic tool: create_ui_action** |
| 1:05 | Switch to Translator mode via Mode Selector | Mode selector strip highlights Translator | **Mid-session mode switching** |

**Key moments to nail:**
- The barge-in MUST be obvious — interrupt the AI while it's speaking
- Show the orb/wave visualizer animating during AI speech
- Show Smart Action Cards appearing automatically
- The mode switch should be smooth and visible

---

### SCENE 3: TRANSLATOR MODE (1:10 – 1:55) — 45 seconds

**What's on screen:** Phone showing Translator mode with camera pointed at foreign text.

**Setup:** Hold up a printed Spanish/French menu or sign.

| Timestamp | You Say | Arqivon Does | What Judges See |
|-----------|---------|-------------|-----------------|
| 1:10 | "I'm at a restaurant and I can't read this menu" | AI begins: "Let me take a look..." | Natural conversation |
| 1:15 | Point camera at the Spanish/French menu | Translation overlay appears with source → target text | **Vision + Translation overlay UI** |
| 1:22 | "What about that second item?" | AI reads and translates the specific item | **Context-aware follow-up** |
| 1:30 | "Can you translate that to Japanese instead?" | Overlay updates with Japanese translation | **Multi-language support** |
| 1:38 | "Export this as a document" | Export card appears → native share sheet opens | **Agentic tool: export_document + PDF** |
| 1:45 | "Detect what language the original is in" | AI responds with detected language | **Agentic tool: detect_language** |
| 1:50 | Switch to Tutor mode | Mode selector transitions | Mode switching |

**Key moments to nail:**
- Translation overlay must be clearly readable on screen
- Show the source AND target language in the overlay
- The PDF export + share sheet is very impressive → hold on it for 2-3 seconds

---

### SCENE 4: TUTOR MODE (1:55 – 2:40) — 45 seconds

**What's on screen:** Phone showing Tutor mode with camera pointed at a math problem.

**Setup:** Write on paper or whiteboard: `∫(3x² + 2x)dx` or `Solve: 2x + 5 = 13`

| Timestamp | You Say | Arqivon Does | What Judges See |
|-----------|---------|-------------|-----------------|
| 1:55 | "I need help with this math problem" | AI: "I can see the problem, let me walk you through it" | **Vision: reads handwriting** |
| 2:00 | Point camera at the written problem | Tutor Guidance Card appears with step-by-step solution | **Agentic tool: solve_problem** |
| 2:10 | "Can you explain step 2 more?" | Concept explanation card appears | **Agentic tool: explain_concept** |
| 2:18 | "Give me a hint for the next part, don't tell me the answer" | Hint card appears (no spoilers) | **Agentic tool: provide_hint** |
| 2:25 | "I think the answer is x² + x³ + C" | AI grades the attempt with feedback | **Agentic tool: grade_step** |
| 2:32 | "Export the solution" | PDF export with full solution | **export_document** |
| 2:37 | Switch to Support mode | Mode transition | |

**Key moments to nail:**
- The step-by-step solution card is your showpiece — hold on it so judges can read
- Show that video feed is live while tutor card is overlaid
- The hint vs. full solution shows pedagogical nuance

---

### SCENE 5: SUPPORT MODE + ARCHIVE (2:40 – 3:05) — 25 seconds

**What's on screen:** Phone showing Support mode, then Archive.

| Timestamp | You Say | Arqivon Does | What Judges See |
|-----------|---------|-------------|-----------------|
| 2:40 | "I'm having an issue with my order, it hasn't arrived" | AI responds as support agent, topic tracker appears | **Agentic tool: switch_topic** |
| 2:47 | "This is really frustrating, I need to escalate" | Escalation card appears | **Agentic tool: escalate_case** |
| 2:52 | Stop the session | Session saved | Session persistence |
| 2:55 | Navigate to Archive tab | Session list with mode-colored tiles | **Firestore session archive** |
| 3:00 | Tap on a session | Session details with summary, turn count | **AI-generated summary (Gemini Flash Lite)** |

**Key moments to nail:**
- Topic tracker showing conversation topics is unique — make it visible
- Archive showing color-coded sessions by mode is visually appealing

---

### SCENE 6: ARCHITECTURE + GCP PROOF (3:05 – 3:30) — 25 seconds

**What's on screen:** Split between architecture diagram and GCP Console.

**How to record this:**
1. Open the architecture diagram PNG full-screen on your Mac
2. Record your Mac screen for 8 seconds on the diagram
3. Then switch to `console.cloud.google.com` → Cloud Run → arqivon-backend
4. Show the service running, active revisions, and request metrics

> **YOUR VOICEOVER (add in editing):**
>
> "Under the hood, Arqivon runs a FastAPI backend on Google Cloud Run, connected to the Gemini 2.5 Flash Live API through the Google GenAI SDK. Audio and video stream simultaneously over a bidirectional WebSocket. Our 17-tool agentic registry lets Gemini call functions like save-memory, export-PDF, or create-UI-card — bridging AI reasoning with native mobile actions. Sessions persist in Cloud Firestore, authenticated through Firebase Auth."

**GCP Console proof shots (3-4 seconds each):**
1. Cloud Run dashboard showing `arqivon-backend` service → status: Active
2. Revision details showing container specs (512Mi, 1 CPU, min 1 instance)
3. Cloud Run logs showing live WebSocket connections (optional)

---

### SCENE 7: CLOSING (3:30 – 3:50) — 20 seconds

**What's on screen:** Back to the app — show the animated orb one last time, then logo/text overlay.

> **YOUR VOICEOVER:**
>
> "Arqivon isn't just another chatbot — it's a Living Lens that sees, hears, speaks, and acts. Four specialized agent modes, 17 agentic tools, real-time barge-in, and native PDF export — all powered by Gemini and Google Cloud. Try it yourself — link in the description. Arqivon: The Living Lens."

**Final frame (3 seconds):**
- App logo centered
- Text: "Arqivon — The Living Lens"
- Text: "#GeminiLiveAgentChallenge"
- Text: "github.com/Medialordofficial/Arqivon"

---

## 5. Recording Instructions

### Phone Screen Recording via QuickTime

```
1. Connect iPhone/Android to Mac via USB cable
2. Open QuickTime Player
3. File → New Movie Recording
4. Click the dropdown arrow (▾) next to the record button
5. Under "Camera", select your phone
6. Under "Microphone", select your phone (captures AI voice + your voice)
7. Set quality to "Maximum"
8. Click Record
9. Do the demo on your phone — QuickTime captures everything
10. Click Stop when done
```

### GCP Console Screen Recording

```
1. Open QuickTime Player
2. File → New Screen Recording
3. Navigate to console.cloud.google.com
4. Go to Cloud Run → arqivon-backend
5. Record for 15-20 seconds, scrolling through:
   - Service status (Active)
   - Latest revision details
   - Metrics tab (if graphs show traffic)
6. Stop recording
```

### Voiceover Recording

```
1. Open Voice Memos (macOS) or Audacity
2. Use your best mic (AirPods Pro work well)
3. Sit in the quietest room possible
4. Record each voiceover segment separately:
   - Hook narration (0:00-0:25)
   - Architecture narration (3:05-3:30)
   - Closing narration (3:30-3:50)
5. Speak clearly, medium pace, with confidence
6. Do 3 takes of each — pick the best
```

### Pro Tips During Recording

- **DO NOT rush.** Let each UI element appear and be visible for 2+ seconds
- **Speak naturally** to the AI — don't read from a script robotically
- **If the AI gives a bad answer**, just redo that segment. You'll edit it together
- **Record MORE than you need** — it's easier to cut than to reshoot
- **Keep your finger movements slow** — fast taps look messy on video
- **Hold the camera steady** when pointing at props — judges need to see what the AI sees
- **Record each mode separately** — you'll stitch them together in editing

---

## 6. Editing Instructions

### Timeline Layout

```
Video Track 1:  [Hook Montage][Assistant Demo][Translator Demo][Tutor Demo][Support+Archive][Architecture][Close]
Video Track 2:  [Architecture diagram PNG/animation overlay during Scene 6]
Audio Track 1:  [Phone audio — your voice + AI voice throughout demos]
Audio Track 2:  [Voiceover narration — Scenes 1, 6, 7 only]
Audio Track 3:  [Background music — subtle, low volume]
Text Track:     [Labels, timestamps, tool names appearing during demos]
```

### Text Overlays to Add

Add these text callouts during the demo to highlight features for judges:

| When | Text Overlay | Duration |
|------|-------------|----------|
| 0:25 | `🔴 LIVE — Gemini 2.5 Flash Native Audio` | 3s |
| 0:47 | `⚡ BARGE-IN — Voice Activity Detection` | 3s |
| 0:55 | `🛠️ Tool: create_ui_action` | 2s |
| 1:10 | `🌐 TRANSLATOR MODE` | 2s |
| 1:15 | `📷 Real-Time Vision + Translation` | 3s |
| 1:38 | `📄 Tool: export_document → PDF` | 2s |
| 1:55 | `🎓 TUTOR MODE` | 2s |
| 2:00 | `🛠️ Tool: solve_problem (step-by-step)` | 3s |
| 2:40 | `🎧 SUPPORT MODE` | 2s |
| 2:47 | `🛠️ Tool: escalate_case` | 2s |
| 3:05 | `☁️ Architecture — Google Cloud Native` | 3s |

### Background Music

- Use **royalty-free** music from:
  - YouTube Audio Library (free, built into YouTube Studio)
  - Pixabay Music (free, no attribution required)
  - Uppbeat (free tier)
- Choose: **ambient electronic, low-key, modern** — think Apple keynote background music
- Volume: **10-15%** of main audio — it should barely be noticeable
- **MUTE music during live AI conversation** — judges need to hear the AI voice clearly
- Fade music in only during voiceover sections (hook, architecture, closing)

### Color & Polish

- **Brightness/Contrast:** Boost slightly if phone screen looks dim in recording
- **Transitions:** Simple cross-dissolves (0.3s) between scenes. NO fancy transitions
- **Aspect ratio:** 16:9 horizontal. If phone recording is vertical, place on dark background with blur
- **Resolution:** Export at 1080p minimum, 4K preferred
- **Frame rate:** 30fps

---

## 7. Upload & Submission

### YouTube Upload

```
1. Go to studio.youtube.com
2. Upload the final video
3. Title: "Arqivon — The Living Lens | Gemini Live Agent Challenge"
4. Description:
   
   Arqivon is a real-time multimodal AI Live Agent powered by Gemini 2.5 Flash 
   and Google Cloud. It transforms your phone into an intelligent Living Lens 
   that sees, hears, speaks, and acts through 4 specialized agent modes and 
   17 agentic tools.

   Built for the Gemini Live Agent Challenge #GeminiLiveAgentChallenge

   🔗 GitHub: https://github.com/Medialordofficial/Arqivon
   🔗 Landing: https://arqivon-inc.web.app
   🔗 Privacy: https://arqivon-inc.web.app/privacy

   Technologies: Gemini Live API, Google GenAI SDK, Google Cloud Run, 
   Firebase Auth, Cloud Firestore, Flutter, FastAPI

5. Tags: Gemini, Google Cloud, Live API, AI Agent, Multimodal, Flutter, 
   GeminiLiveAgentChallenge, Hackathon
6. Visibility: PUBLIC (not unlisted — rules require public)
7. Category: Science & Technology
8. Add English subtitles (YouTube auto-generates, then review/fix them)
```

### Devpost Submission Fields

| Field | What to Enter |
|-------|---------------|
| **Project Name** | Arqivon — The Living Lens |
| **Category** | Live Agents |
| **Video URL** | Your YouTube link |
| **Repository URL** | https://github.com/Medialordofficial/Arqivon |
| **Description** | See README.md content — summarize features, modes, tech stack |
| **Technologies Used** | Gemini Live API, Google GenAI SDK, Google Cloud Run, Cloud Firestore, Firebase Auth, Firebase Hosting, Flutter, FastAPI, Python |
| **Architecture Diagram** | Upload architecture.png |
| **GCP Proof** | Link to deploy.sh in repo + mention Cloud Run URL |
| **Third-Party Integrations** | List from README Third-Party section |

---

## 8. Common Mistakes to Avoid

### ❌ DON'T

1. **Don't show slides or bullet points** — judges want working software, not PowerPoint
2. **Don't go over 4 minutes** — only the first 4 minutes are evaluated
3. **Don't use unlisted visibility** — rules require PUBLIC YouTube/Vimeo
4. **Don't have background noise** — record in a quiet room; AI voice must be clear
5. **Don't rush through features** — let each UI element be visible for 2+ seconds
6. **Don't fake or mock anything** — "no mockups; show the actual software"
7. **Don't spend more than 25s on architecture** — judges care more about the live demo
8. **Don't forget English subtitles** — required by rules
9. **Don't show errors or crashes** — test everything beforehand, re-record if needed
10. **Don't narrate over the AI voice** — let judges hear the AI responding naturally

### ✅ DO

1. **Show barge-in prominently** — this is THE Live Agent differentiator (explicitly scored)
2. **Show all 4 modes** — demonstrates breadth and agent persona variety
3. **Show function calls in action** — smart action cards, export, memory saving
4. **Show the camera + voice working SIMULTANEOUSLY** — multimodal = both at once
5. **Show the PDF export** — this is a "wow" moment that other projects won't have
6. **Show Cloud Run proof** — GCP console screenshot, even briefly
7. **Include the architecture diagram** — required in submission, show it in video too
8. **Start strong** — first 10 seconds determine if judges keep watching
9. **End with your name/logo/hashtag** — professional polish matters
10. **Review YouTube auto-captions** — fix any AI/technical term errors

---

## Ideal Recording Schedule

| Day | Task | Time |
|-----|------|------|
| **Day 1** | Gather props, print foreign text, write math problem | 30 min |
| **Day 1** | Practice demo script with app 3x | 45 min |
| **Day 2** | Record all phone demo footage (Scenes 2-5) | 1-2 hours |
| **Day 2** | Record GCP Console footage (Scene 6) | 15 min |
| **Day 2** | Record voiceover narration (Scenes 1, 6, 7) | 30 min |
| **Day 3** | Edit video, add text overlays, music | 2-3 hours |
| **Day 3** | Export, upload to YouTube, add subtitles | 30 min |
| **Day 3** | Submit to Devpost | 15 min |

**Total effort: ~6-8 hours across 3 days**

---

## Quick Reference Card

```
VIDEO LENGTH:     3:50 max (aim for 3:40-3:50)
RESOLUTION:       1080p or 4K, 16:9, 30fps
UPLOAD:           YouTube, PUBLIC visibility
SUBTITLES:        English (auto-generate + review)
MUSIC:            Royalty-free, 10-15% volume, muted during AI talk
KEY MOMENTS:      Barge-in, camera+voice simultaneous, PDF export, 4 modes
ARCHITECTURE:     Show diagram + GCP Console (< 25 seconds total)
HASHTAG:          #GeminiLiveAgentChallenge
```
