# Arqivon Live Conversation Stress Checklist

Goal: verify competition-grade smoothness for real-time multimodal conversation, interruptions, tool use, and recovery.

## Test Setup
- Build used: latest release APK
- Device: Android physical device
- Network: stable Wi-Fi, then flaky network test
- Session length target: at least 20 minutes continuous conversation

## Pass Criteria (global)
- No stuck Listening state
- No silent AI after text transcript appears
- Interruption always cuts AI audio immediately
- AI responds to interruption context (does not continue stale answer)
- No app crash, freeze, or forced restart

## A. Core Turn-Taking (5 tests)
1) Start a fresh session and ask 5 short questions back-to-back.
- Expected: all 5 get spoken answers with matching transcript.

2) Ask one long question (20-30 seconds speech).
- Expected: full response audio, no truncation, no dead air > 3 seconds after turn end.

3) Do 10 rapid turns (short question, short answer rhythm).
- Expected: no drift; voice remains active through all turns.

4) Pause silently for 20 seconds with camera on.
- Expected: no broken state; if ambient nudge occurs, it is coherent.

5) End session and immediately start again.
- Expected: new session starts cleanly, no stale transcript/audio.

## B. Interruption and Barge-In (6 tests)
6) Interrupt AI in the first second of playback.
- Expected: AI audio stops immediately; new user speech is captured and answered.

7) Interrupt near the end of AI playback.
- Expected: old response does not resume; AI follows new prompt.

8) Interrupt AI 5 times in one minute.
- Expected: no mic death, no stuck responding state.

9) Interrupt while switching topic mid-answer.
- Expected: AI follows new topic and does not keep old thread.

10) Interrupt then stay silent.
- Expected: app returns to listening state without locking.

11) Interrupt with camera-based request (show object + speak).
- Expected: model processes latest multimodal context correctly.

## C. Multimodal + Tools (5 tests)
12) Show text in camera and ask to read/summarize.
- Expected: spoken summary + correct transcript alignment.

13) Ask to save note during active conversation.
- Expected: note_saved UI confirmation appears once, no duplicated cards.

14) Ask to set reminder during active conversation.
- Expected: reminder_set confirmation appears and conversation continues naturally.

15) In translator mode, alternate speech and camera text.
- Expected: translation overlay updates correctly, spoken output stays in target language.

16) In tutor/support mode, trigger at least one tool call each.
- Expected: tool card appears and AI remains conversational (no stall after tool).

## D. Switching + Recovery (6 tests)
17) Switch mode while AI is speaking.
- Expected: old audio stops; new mode responds correctly.

18) Switch voice during conversation.
- Expected: status updates, new voice used on next response.

19) Leave Live tab and return, then resume speaking.
- Expected: no stuck Listening; responds normally.

20) Toggle mute/unmute while streaming.
- Expected: muted sends no audio; unmute resumes within 1-2 seconds.

21) Simulate brief network drop (disable internet 5-10s, then restore).
- Expected: recovers without force-closing app; next utterance works.

22) Run continuous 20-minute mixed conversation.
- Expected: no long-tail silent-audio failure.

## E. Failure Logging (if any)
For each failure capture:
- Timestamp
- Mode
- Last user utterance
- Whether transcript appeared
- Whether AI audio played
- Whether interruption was involved
- Device network state

## Release Gate
Ship candidate only if all sections pass with zero blocker failures.
Blockers:
- Any stuck Listening/Responding state
- Any silent-audio-with-transcript event
- Any interruption ignored or causing lost turn
- Any crash/freeze in live flow
