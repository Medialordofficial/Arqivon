# Arqivon Demo Video Storyboard (< 4 Minutes)

**Scene 1: The Hook (0:00 - 0:30)**
- **Visual:** Fast-paced montage. User opens Arqivon, points camera at a messy desk.
- **Audio (User):** "Arqivon, what am I looking at?"
- **Audio (Arqivon - Aoede Voice):** "I see a laptop, a coffee mug, and a business card for John Doe."
- **Visual:** A "Smart Action Card" instantly pops up on the camera feed: *[Save Contact: John Doe]*. User taps 'Check'.
- **Narration:** "Meet Arqivon. The multimodal Live Agent that sees, hears, and acts in real-time."

**Scene 2: Zero-Latency Interruptibility (0:30 - 1:15)**
- **Visual:** User is walking outside, camera pointing at a street sign in Spanish.
- **Audio (User):** "Can you translate that sign for me? It says..."
- **Audio (Arqivon):** "It translates to 'No Parking between—'"
- **Audio (User - Interrupting):** "Wait, what about the smaller text below it?"
- **Visual:** UI shows Arqivon instantly muting and listening.
- **Audio (Arqivon):** "Ah, the smaller text says 'Tow Away Zone'."
- **Narration:** "Powered by Gemini 3.1 Pro Preview, Arqivon supports native Voice Activity Detection for seamless, natural conversations."

**Scene 3: Agentic Tool Registry & UI Actions (1:15 - 2:15)**
- **Visual:** Split screen. Left: Flutter App. Right: Backend logs showing Function Calling.
- **Audio (User):** "Remind me to buy milk tomorrow at 5 PM."
- **Visual (Right):** Logs show `upsert_firestore_memory` and `create_ui_action` being triggered.
- **Visual (Left):** A Glassmorphism UI card slides in: *[Calendar Event Created: Buy Milk]*.
- **Narration:** "Our backend Tool Registry leverages the GenAI SDK to bridge the gap between AI reasoning and native Flutter UI rendering."

**Scene 4: The Archive & Settings (2:15 - 3:00)**
- **Visual:** User navigates to the 'Archive' tab. Beautifully animated list of past sessions.
- **Visual:** User taps a session. The context reloads.
- **Visual:** User navigates to 'Settings', toggles Dark Mode, and changes the AI voice to 'Fenrir'.
- **Narration:** "All sessions are securely backed by Firestore with strict security rules, ensuring your multimodal memories are always accessible and private."

**Scene 5: Architecture & Outro (3:00 - 3:45)**
- **Visual:** The Mermaid.js architecture diagram animates on screen, highlighting the WebSocket flow through Cloud Run to the Gemini Live API.
- **Narration:** "Built for production. Containerized on Cloud Run with zero cold starts, bidirectional WebSockets, and Riverpod state management."
- **Visual:** Final logo splash: "Arqivon: The Living Lens. Vote for us in the Gemini Live Agent Challenge."
