"""
Arqivon Backend – FastAPI + Gemini Live API relay.

Production-grade WebSocket relay between Flutter clients and the Gemini
multimodal Live API with function-calling, mode-aware system prompts,
session persistence, heartbeat keep-alive, and exponential-backoff
reconnection.  Supports four agent modes:
  • general     – proactive multimodal assistant
  • translator  – real-time multilingual translator
  • tutor       – vision-enabled smart tutor
  • support     – voice-driven customer support agent
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import random
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware

import firebase_admin
from firebase_admin import credentials, firestore as fb_firestore, storage, auth as fb_auth, messaging as fb_messaging

from google import genai
from google.genai import types

from config import settings
from models import (
    AgentMode,
    InboundMessage, InboundType,
    OutboundMessage, OutboundType,
    SessionRecord,
)
from tool_registry import get_tool_declarations, dispatch_tool_call

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("arqivon")

# ── Globals ───────────────────────────────────────────────────────────────────

db: Any = None
gcs_bucket: Any = None
genai_client: genai.Client | None = None


# ── Latency tracer ────────────────────────────────────────────────────────────

class LatencyTracer:
    """Per-session latency tracker that measures every hop in the pipeline.

    Tracks: audio_in (client→backend), gemini_send, gemini_first_token,
    gemini_turn, tool_dispatch, audio_out (backend→client), and frame_send.
    Periodically logs P50/P95/P99 for each span and exposes a summary dict.
    """

    __slots__ = ("_spans", "_starts", "_log_interval", "_last_log", "session_id")

    def __init__(self, session_id: str, log_interval: float = 30.0):
        self.session_id = session_id
        self._log_interval = log_interval
        self._last_log = time.monotonic()
        self._spans: dict[str, list[float]] = {}
        self._starts: dict[str, float] = {}

    def start(self, name: str) -> None:
        self._starts[name] = time.monotonic()

    def end(self, name: str) -> float:
        t0 = self._starts.pop(name, None)
        if t0 is None:
            return 0.0
        elapsed_ms = (time.monotonic() - t0) * 1000
        self._spans.setdefault(name, []).append(elapsed_ms)
        self._maybe_log()
        return elapsed_ms

    def record(self, name: str, ms: float) -> None:
        self._spans.setdefault(name, []).append(ms)
        self._maybe_log()

    def _maybe_log(self) -> None:
        now = time.monotonic()
        if now - self._last_log < self._log_interval:
            return
        self._last_log = now
        summary = self.summary()
        if summary:
            logger.info("LATENCY[%s]: %s", self.session_id[:8], summary)

    def summary(self) -> dict[str, dict[str, float]]:
        result: dict[str, dict[str, float]] = {}
        for name, values in self._spans.items():
            if not values:
                continue
            s = sorted(values)
            n = len(s)
            result[name] = {
                "count": n,
                "p50": s[n // 2],
                "p95": s[int(n * 0.95)] if n >= 2 else s[-1],
                "p99": s[int(n * 0.99)] if n >= 2 else s[-1],
                "max": s[-1],
            }
        return result


# ── Async input queue with interrupt-flush ─────────────────────────────────

class InputQueue:
    """Async priority queue for client inputs.

    Audio has highest priority and is forwarded immediately.  Video frames
    are deduplicated — only the most recent queued frame is kept.
    When the user interrupts (barge-in), `flush()` drops all pending
    non-audio items so the new utterance gets clean context.
    """

    def __init__(self):
        self._audio_q: asyncio.Queue[bytes] = asyncio.Queue(maxsize=200)
        self._video_frame: bytes | None = None  # latest-wins slot
        self._video_ready = asyncio.Event()

    async def put_audio(self, data: bytes) -> None:
        try:
            self._audio_q.put_nowait(data)
        except asyncio.QueueFull:
            # Drop oldest audio chunk to prevent backpressure
            try:
                self._audio_q.get_nowait()
            except asyncio.QueueEmpty:
                pass
            self._audio_q.put_nowait(data)

    def put_video(self, data: bytes) -> None:
        """Latest-wins: only keep the most recent video frame."""
        self._video_frame = data
        self._video_ready.set()

    async def get_video(self) -> bytes | None:
        """Wait for a video frame; returns None if flushed."""
        await self._video_ready.wait()
        frame = self._video_frame
        self._video_frame = None
        self._video_ready.clear()
        return frame

    def flush(self) -> None:
        """Drop pending VIDEO on interrupt (barge-in).

        Audio is NOT flushed — the chunks the user is speaking right now
        during the barge-in must reach Gemini so it can process the new
        utterance.  Only stale video frames are dropped.
        """
        self._video_frame = None
        self._video_ready.clear()


# ── Video frame throttle / deduplication ───────────────────────────────────

class FrameThrottle:
    """Drop frames that arrive faster than the minimum interval."""

    __slots__ = ("_min_interval", "_last_sent", "_dropped")

    def __init__(self, min_interval: float = 0.30):
        self._min_interval = min_interval
        self._last_sent = 0.0
        self._dropped = 0

    def should_send(self) -> bool:
        now = time.monotonic()
        if now - self._last_sent < self._min_interval:
            self._dropped += 1
            return False
        self._last_sent = now
        return True

    @property
    def dropped(self) -> int:
        return self._dropped

    @property
    def last_sent_time(self) -> float:
        """Monotonic timestamp of the last frame actually sent."""
        return self._last_sent


# ── Mode-specific system instructions ────────────────────────────────────────

SYSTEM_PROMPTS: dict[str, str] = {
    AgentMode.GENERAL: (
        "You are Arqivon — the world's most capable real-time multimodal AI assistant. "
        "You see through the user's camera and hear their voice simultaneously in real-time. "
        "You are proactive, brilliant, and extraordinarily helpful.\n\n"

        "CORE CAPABILITIES:\n"
        "• Vision: Read documents, signs, labels, screens, QR codes, barcodes, business cards, "
        "handwriting, whiteboards, receipts, menus, maps — anything the camera shows you.\n"
        "• Audio: Understand speech in 100+ languages with accent awareness.\n"
        "• Knowledge: Deep expertise across every domain — science, technology, engineering, "
        "mathematics, history, geography, medicine, law, finance, art, music, cooking, fitness, "
        "travel, DIY, automotive, real estate, and more.\n"
        "• Actionable Intelligence: When you detect actionable items (phone numbers, addresses, "
        "calendar events, URLs, emails, QR codes, business cards, package tracking numbers, "
        "product prices, recipes), IMMEDIATELY call create_ui_action so the user can act on them.\n"
        "• Memory: When the user says 'remember this' or shares a preference, call "
        "upsert_firestore_memory to persist it across sessions.\n"
        "• Recall: When the user references something from a previous session — e.g. "
        "'compare to the couch we saw before', 'what was the price', 'remember when I "
        "showed you…' — call recall_memories to retrieve stored information. Use the "
        "recalled details to answer accurately.\n\n"

        "PROACTIVE AMBIENT INTELLIGENCE:\n"
        "• When you receive a system nudge like '[AMBIENT]', it means the user is silently "
        "showing you their camera. Look at the current video frames carefully.\n"
        "• If you see something genuinely interesting, useful, or actionable — SPEAK UP "
        "proactively without being asked. Examples:\n"
        "  – 'I notice that product has a recall warning.'\n"
        "  – 'The WiFi password on that sign is ABC123.'\n"
        "  – 'That receipt shows you were overcharged — the total should be $12.50.'\n"
        "  – 'That's the Eiffel Tower — built in 1889 for the World's Fair.'\n"
        "  – 'I can see an error message on your screen — try restarting the app.'\n"
        "• If nothing notable is visible or you've already commented, stay completely silent. "
        "Do NOT say 'I don't see anything interesting' — just say nothing.\n"
        "• Keep proactive observations brief (1-2 sentences). Be helpful, not noisy.\n\n"

        "BEHAVIOR GUIDELINES:\n"
        "• Be concise but thorough — give the complete answer the user needs.\n"
        "• When shown a document, read and summarize it proactively.\n"
        "• When shown a product, identify it and provide useful context (price comparisons, "
        "reviews, ingredients, nutritional info).\n"
        "• When shown a location or landmark, identify it and provide relevant information.\n"
        "• When asked to calculate, solve, or analyze — do it fully and accurately.\n"
        "• Speak naturally and conversationally. Sound human, not robotic.\n"
        "• Anticipate follow-up needs. If someone shows you a receipt, offer to summarize expenses.\n"
        "• You can handle multi-step tasks: planning trips, comparing options, debugging code, "
        "writing emails, creating shopping lists, meal planning, workout routines.\n\n"

        "CRITICAL: Always detect the language the user is speaking and respond in that "
        "exact same language. Never switch languages unless explicitly asked to."
    ),
    AgentMode.TRANSLATOR: (
        "You are Arqivon Translator — the world's most advanced real-time translation engine. "
        "You provide live, broadcast-quality translation across ALL languages with native "
        "fluency, cultural awareness, and context sensitivity.\n\n"

        "SUPPORTED LANGUAGES (you MUST translate between ANY of these):\n"
        "English, Spanish, French, German, Italian, Portuguese, Chinese (Mandarin & Traditional), "
        "Japanese, Korean, Arabic, Hindi, Russian, Turkish, Dutch, Polish, Swedish, Danish, "
        "Norwegian, Finnish, Greek, Czech, Slovak, Romanian, Hungarian, Bulgarian, Croatian, "
        "Serbian, Slovenian, Ukrainian, Lithuanian, Latvian, Estonian, Irish, Welsh, Icelandic, "
        "Maltese, Albanian, Macedonian, Bosnian, Catalan, Galician, Basque, Luxembourgish, "
        "Thai, Vietnamese, Indonesian, Malay, Filipino (Tagalog), Bengali, Tamil, Telugu, "
        "Malayalam, Kannada, Marathi, Gujarati, Punjabi, Urdu, Nepali, Sinhala, Burmese, "
        "Khmer, Lao, Georgian, Armenian, Azerbaijani, Kazakh, Uzbek, Mongolian, Hebrew, "
        "Persian (Farsi), Swahili, Amharic, Hausa, Yoruba, Igbo, Zulu, Xhosa, Afrikaans, "
        "Somali, Kinyarwanda, Malagasy, Shona, Haitian Creole, Quechua, Esperanto, Latin, "
        "Javanese, Sundanese, Cebuano, Chichewa, Corsican, Frisian, Scottish Gaelic, "
        "Kurdish, Pashto, Sindhi, Samoan, Sesotho, Tajik, Turkmen, Tatar, Uyghur, Yiddish, "
        "and any other language you are capable of.\n\n"

        "CORE CAPABILITIES:\n"
        "• Real-Time Speech Translation: Listen to speech in any language and IMMEDIATELY "
        "call live_translate with source_text, translated_text, source_language, and "
        "target_language. Do this for EVERY utterance — even short phrases.\n"
        "• Document Translation via Camera: When the user points the camera at a document, "
        "sign, menu, label, or screen — read ALL the text, translate it completely, and "
        "call live_translate with the full parallel translation.\n"
        "• Cultural Adaptation: Adapt idioms, humor, formality levels, and cultural references. "
        "A Japanese business card gets different treatment than a casual Spanish text message.\n"
        "• Register Awareness: Support formal, informal, and neutral registers. Academic papers "
        "get formal treatment; casual chat gets colloquial translation.\n"
        "• Technical Vocabulary: Handle medical, legal, technical, and scientific terminology "
        "with domain-appropriate translations.\n"
        "• Saveable Flashcards: For important phrases, vocabulary, or culturally significant "
        "expressions, call translation_card to create a saveable flashcard the user can review.\n\n"

        "BEHAVIOR GUIDELINES:\n"
        "• ALWAYS call live_translate — this is what makes subtitles appear on screen.\n"
        "• Speak the translated text aloud in the target language with proper pronunciation.\n"
        "• For documents shown via camera: translate the ENTIRE visible text, not just a summary.\n"
        "• Handle interruptions gracefully — if the user speaks mid-translation, immediately "
        "stop and translate the new input.\n"
        "• Detect language automatically when set to 'auto'.\n"
        "• For ambiguous translations, briefly explain the nuance.\n"
        "• When translating large documents, organize output by paragraphs/sections.\n\n"

        "CRITICAL: Respond in the user's language when conversing, but translate INTO the "
        "target language when performing translations. Never mix the two."
    ),
    AgentMode.TUTOR: (
        "You are Arqivon Tutor — the world's smartest genius-level tutor and educator. "
        "You have PhD-level knowledge across EVERY academic discipline and can teach anyone "
        "from kindergarten to postdoctoral level. You are patient, encouraging, and adaptive.\n\n"

        "KNOWLEDGE DOMAINS (you are an expert in ALL of these):\n"
        "• Mathematics: Arithmetic, algebra, geometry, trigonometry, calculus (single/multi-variable), "
        "linear algebra, differential equations, number theory, combinatorics, statistics, probability, "
        "discrete math, topology, abstract algebra, real/complex analysis.\n"
        "• Physics: Classical mechanics, thermodynamics, electromagnetism, optics, quantum mechanics, "
        "relativity, nuclear physics, particle physics, astrophysics, fluid dynamics.\n"
        "• Chemistry: Organic, inorganic, physical, analytical, biochemistry, polymer chemistry, "
        "electrochemistry, thermochemistry, spectroscopy.\n"
        "• Biology: Cell biology, genetics, molecular biology, ecology, evolution, anatomy, "
        "physiology, microbiology, immunology, neuroscience, botany, zoology.\n"
        "• Computer Science: Programming (Python, Java, C++, JavaScript, Rust, Go), algorithms, "
        "data structures, databases, networking, OS, AI/ML, cybersecurity, web dev, mobile dev.\n"
        "• Engineering: Civil, mechanical, electrical, chemical, aerospace, biomedical, software.\n"
        "• Humanities: History (world, ancient, modern), philosophy, literature, linguistics, "
        "anthropology, sociology, psychology, political science, economics.\n"
        "• Languages: Grammar, writing, essay structure, literary analysis in 50+ languages.\n"
        "• Geography: Physical, human, geopolitics, cartography, climate science, geology.\n"
        "• Medicine: Anatomy, pharmacology, pathology, diagnostics, public health.\n"
        "• Business: Accounting, finance, marketing, management, entrepreneurship, strategy.\n"
        "• Arts: Music theory, art history, film, architecture, design principles.\n\n"

        "CORE CAPABILITIES:\n"
        "• Solve ANY Problem: When asked to solve a math problem, equation, physics problem, "
        "chemistry balance, coding challenge, or any academic question — SOLVE IT FULLY. "
        "Show complete step-by-step working. Give the final answer clearly.\n"
        "• Vision-Based Learning: When the student shows homework, textbook pages, diagrams, "
        "equations, graphs, code, lab reports, or exam questions via camera — read them, "
        "understand them, and help immediately.\n"
        "• Adaptive Teaching: Match your explanation level to the student. A 10-year-old asking "
        "about fractions gets different treatment than a grad student asking about Fourier transforms.\n"
        "• Call analyze_homework to identify the subject and problem type.\n"
        "• Call provide_hint when the student ASKS for hints (but give full answers when asked).\n"
        "• Call grade_step when reviewing the student's attempt.\n"
        "• Call tutor_card to render progress/explanation cards on screen.\n\n"

        "CRITICAL BEHAVIOR:\n"
        "• When a student says 'solve this', 'what's the answer', 'help me with this' — "
        "GIVE THE COMPLETE SOLUTION with step-by-step working. Do NOT withhold answers.\n"
        "• When a student says 'teach me', 'explain this', 'I don't understand' — "
        "explain the concept clearly with examples before solving.\n"
        "• When a student says 'check my work' — use grade_step to evaluate their attempt.\n"
        "• When a student says 'give me a hint' — use provide_hint (Socratic method).\n"
        "• For assignments: read the full problem, solve it completely, explain each step.\n"
        "• For essays: help with structure, thesis, arguments, evidence, and writing quality.\n"
        "• For code: write working code, explain the logic, suggest improvements.\n"
        "• Be encouraging but honest. Celebrate correct steps, gently correct mistakes.\n\n"

        "CRITICAL: Always detect the language the user is speaking and respond in that "
        "exact same language. Never switch languages unless explicitly asked to."
    ),
    AgentMode.SUPPORT: (
        "You are Arqivon Support — an elite AI support agent with the knowledge and empathy "
        "of the world's best customer service professionals. You handle any type of support "
        "request with professionalism, speed, and accuracy.\n\n"

        "SUPPORT DOMAINS:\n"
        "• Technical Support: Troubleshoot devices, software, networks, apps, accounts, "
        "connectivity issues, error messages, configurations, installations.\n"
        "• Product Support: Help with purchases, returns, warranties, product comparisons, "
        "usage guides, feature discovery.\n"
        "• Service Support: Billing, subscriptions, account management, plan changes.\n"
        "• General Knowledge Support: Answer questions about government services, healthcare, "
        "legal rights, travel, immigration, education systems, financial services.\n"
        "• How-To Support: Step-by-step guides for anything — cooking, DIY, fitness, "
        "home maintenance, gardening, crafts, automotive repair.\n\n"

        "CORE CAPABILITIES:\n"
        "• Track topic changes with switch_topic when the customer shifts subjects.\n"
        "• When you resolve an issue, call log_resolution with the outcome.\n"
        "• If you cannot resolve, call escalate_case with severity and summary.\n"
        "• Use support_card to render contextual action cards with options.\n"
        "• Vision: When the user shows you an error screen, device, product, document, "
        "or anything via camera — read it and address the issue immediately.\n\n"

        "BEHAVIOR GUIDELINES:\n"
        "• Be professional but warm — like the best human support agent.\n"
        "• Anticipate needs: if someone asks about returns, proactively mention the refund timeline.\n"
        "• Handle topic switching gracefully: acknowledge, summarize previous topic, transition.\n"
        "• If the user says 'go back to…', resume the previous topic seamlessly.\n"
        "• Provide clear, actionable steps. Number them for clarity.\n"
        "• Confirm understanding before proceeding with complex troubleshooting.\n"
        "• Never say 'I can't help with that' — always find something useful to offer.\n\n"

        "CRITICAL: Always detect the language the user is speaking and respond in that "
        "exact same language. Never switch languages unless explicitly asked to."
    ),
}


# ── Lifespan ──────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(application: FastAPI):
    global db, gcs_bucket, genai_client

    # Firebase
    try:
        firebase_admin.initialize_app()
        db = fb_firestore.client()
        if settings.gcs_bucket:
            gcs_bucket = storage.bucket(settings.gcs_bucket)
        logger.info("Firebase initialized successfully")
    except Exception as exc:
        logger.warning("Firebase init skipped: %s", exc)

    # GenAI
    if settings.gemini_api_key:
        genai_client = genai.Client(api_key=settings.gemini_api_key)
    else:
        genai_client = genai.Client()
    logger.info("GenAI client ready (model=%s)", settings.gemini_model)

    yield
    logger.info("Shutting down")


app = FastAPI(title="Arqivon API", version="2.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://arqivon-backend-653546103163.us-central1.run.app",
        "https://arqivon.com",
        "https://arqivon-inc.web.app",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model": settings.gemini_model,
        "firebase": db is not None,
        "modes": [m.value for m in AgentMode],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/api/sessions/{user_id}")
async def list_sessions(user_id: str, token: str | None = None):
    # Authenticate via Bearer token query param
    if not token:
        raise HTTPException(401, "Missing auth token")
    try:
        decoded = fb_auth.verify_id_token(token)
        if decoded.get("uid") != user_id:
            raise HTTPException(403, "UID mismatch")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(401, f"Invalid token: {exc}")

    if db is None:
        raise HTTPException(503, "Firestore unavailable")
    docs = await asyncio.to_thread(
        lambda: list(
            db.collection("users")
            .document(user_id)
            .collection("sessions")
            .order_by("started_at", direction=fb_firestore.Query.DESCENDING)
            .limit(50)
            .stream()
        )
    )
    return [doc.to_dict() | {"id": doc.id} for doc in docs]


# ── Daily Briefing endpoint (triggered by Cloud Scheduler) ────────────────

@app.post("/api/daily-briefing/{user_id}")
async def send_daily_briefing(user_id: str, api_key: str | None = None):
    """Generate and send a personalized daily briefing via FCM.

    Designed to be triggered by Google Cloud Scheduler via an HTTP POST.
    For security, requires internal API key or service account auth.
    """
    # Simple API key auth for Cloud Scheduler (check env BRIEFING_API_KEY)
    expected_key = settings.briefing_api_key if hasattr(settings, 'briefing_api_key') else ""
    if expected_key and api_key != expected_key:
        raise HTTPException(403, "Invalid API key")

    if db is None or genai_client is None:
        raise HTTPException(503, "Backend services unavailable")

    # Fetch user's FCM token
    user_doc = await asyncio.to_thread(
        db.collection("users").document(user_id).get
    )
    if not user_doc.exists:
        raise HTTPException(404, "User not found")
    user_data = user_doc.to_dict()
    fcm_token = user_data.get("fcmToken")
    if not fcm_token:
        raise HTTPException(404, "No FCM token for user")

    # Gather context: memories + recent sessions
    memories_text = ""
    try:
        mem_docs = await asyncio.to_thread(
            lambda: list(
                db.collection("users").document(user_id)
                .collection("memories").stream()
            )
        )
        if mem_docs:
            items = [f"• {d.id}: {d.to_dict().get('details', '')}" for d in mem_docs]
            memories_text = "\n".join(items[:20])
    except Exception:
        pass

    sessions_text = ""
    try:
        sess_docs = await asyncio.to_thread(
            lambda: list(
                db.collection("users").document(user_id)
                .collection("sessions")
                .order_by("started_at", direction=fb_firestore.Query.DESCENDING)
                .limit(5)
                .stream()
            )
        )
        if sess_docs:
            items = []
            for d in sess_docs:
                sd = d.to_dict()
                items.append(f"• [{sd.get('mode', 'general')}] {sd.get('title', 'Untitled')}: {sd.get('summary', 'No summary')}")
            sessions_text = "\n".join(items)
    except Exception:
        pass

    # Generate briefing with Gemini
    briefing_prompt = (
        "You are generating a personalized daily briefing notification for a user of Arqivon, "
        "an AI assistant app. Based on their stored memories and recent sessions, create a "
        "brief, engaging morning update (2-3 sentences max). Focus on actionable insights, "
        "follow-ups, or interesting observations. Be warm and helpful.\n\n"
        f"User's stored memories:\n{memories_text or 'None'}\n\n"
        f"Recent sessions:\n{sessions_text or 'None'}\n\n"
        "Generate a concise, personalized daily briefing:"
    )

    try:
        resp = await genai_client.aio.models.generate_content(
            model="gemini-2.0-flash-lite",
            contents=briefing_prompt,
        )
        briefing_text = resp.text.strip() if resp.text else "Good morning! Open Arqivon to start your day."
    except Exception as exc:
        logger.warning("Briefing generation failed: %s", exc)
        briefing_text = "Good morning! Open Arqivon — your AI assistant is ready."

    # Send via FCM
    message = fb_messaging.Message(
        notification=fb_messaging.Notification(
            title="☀️ Your Daily Briefing",
            body=briefing_text[:200],
        ),
        data={"type": "daily_briefing"},
        token=fcm_token,
    )
    await asyncio.to_thread(fb_messaging.send, message)
    logger.info("Daily briefing sent to user %s", user_id)
    return {"status": "sent", "briefing": briefing_text}


@app.post("/api/daily-briefing-all")
async def send_daily_briefing_all(api_key: str | None = None):
    """Send daily briefings to all users with FCM tokens.

    Designed for Cloud Scheduler: POST /api/daily-briefing-all?api_key=...
    """
    expected_key = settings.briefing_api_key if hasattr(settings, 'briefing_api_key') else ""
    if expected_key and api_key != expected_key:
        raise HTTPException(403, "Invalid API key")

    if db is None:
        raise HTTPException(503, "Firestore unavailable")

    # Find all users with FCM tokens
    users_ref = db.collection("users")
    user_docs = await asyncio.to_thread(lambda: list(users_ref.stream()))

    sent = 0
    errors = 0
    for user_doc in user_docs:
        data = user_doc.to_dict()
        if not data.get("fcmToken"):
            continue
        try:
            await send_daily_briefing(user_doc.id, api_key=api_key)
            sent += 1
        except Exception as exc:
            logger.warning("Briefing failed for %s: %s", user_doc.id, exc)
            errors += 1

    logger.info("Daily briefing batch: sent=%d errors=%d", sent, errors)
    return {"status": "complete", "sent": sent, "errors": errors}


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _send_json(ws: WebSocket, msg: OutboundMessage) -> None:
    try:
        await ws.send_text(msg.model_dump_json())
    except Exception as exc:
        logger.debug("_send_json failed (type=%s): %s", msg.type, exc)


async def _save_session(user_id: str, record: SessionRecord) -> None:
    if db is None:
        return
    try:
        def _sync_save():
            (
                db.collection("users")
                .document(user_id)
                .collection("sessions")
                .document(record.session_id)
                .set(record.model_dump(), merge=True)
            )
        await asyncio.to_thread(_sync_save)
        logger.info("Session %s saved for user %s", record.session_id, user_id)
        # Send FCM push notification to the user's device.
        await _send_session_notification(user_id, record)
    except Exception as exc:
        logger.error("Failed to save session: %s", exc)


async def _send_session_notification(user_id: str, record: SessionRecord) -> None:
    """Send a push notification via FCM when a session is saved."""
    if db is None:
        return
    try:
        user_doc = await asyncio.to_thread(
            db.collection("users").document(user_id).get
        )
        if not user_doc.exists:
            return
        fcm_token = user_doc.to_dict().get("fcmToken")
        if not fcm_token:
            logger.debug("No FCM token for user %s — skipping notification", user_id)
            return
        title = record.title or "Session Saved"
        body = record.summary or f"Your {record.mode} session has been archived."
        message = fb_messaging.Message(
            notification=fb_messaging.Notification(
                title=f"\U0001f4be {title}",
                body=body[:200],
            ),
            data={
                "session_id": record.session_id,
                "mode": record.mode,
            },
            token=fcm_token,
        )
        await asyncio.to_thread(fb_messaging.send, message)
        logger.info("FCM notification sent to user %s", user_id)
    except Exception as exc:
        # Non-critical — don't let notification failure break the flow.
        logger.warning("FCM notification failed for %s: %s", user_id, exc)


def _backoff(attempt: int, base: float = 0.5, cap: float = 30.0) -> float:
    delay = min(base * (2 ** attempt), cap)
    return delay + random.uniform(0, delay * 0.1)


async def _connect_gemini(mode: str, source_lang: str, target_lang: str, voice: str = "Aoede", user_id: str = "anonymous", prior_context: str | None = None):
    """Build a LiveConnectConfig for the given mode and open a session.

    Fetches stored memories for the user and injects them into the system
    prompt so the AI has cross-session context from the start.
    If *prior_context* is provided (session resume), it is appended to the
    system prompt so the AI can continue a previous conversation.
    """
    prompt = SYSTEM_PROMPTS.get(mode, SYSTEM_PROMPTS[AgentMode.GENERAL])
    # Inject language context for translator mode
    if mode == AgentMode.TRANSLATOR:
        prompt += (
            f"\nThe user's source language is '{source_lang}' "
            f"(auto means detect automatically). "
            f"The target translation language is '{target_lang}'."
        )

    # ── Inject stored memories into the system prompt ─────────────────
    if db is not None:
        try:
            docs = await asyncio.to_thread(
                lambda: list(
                    db.collection("users").document(user_id)
                    .collection("memories").stream()
                )
            )
            if docs:
                memory_lines = []
                for doc in docs:
                    data = doc.to_dict()
                    topic = doc.id
                    details = data.get("details", "")
                    memory_lines.append(f"  • {topic}: {details}")
                if memory_lines:
                    prompt += (
                        "\n\nUSER'S STORED MEMORIES (from previous sessions):\n"
                        + "\n".join(memory_lines)
                        + "\n\nUse these memories when the user references past observations, "
                        "comparisons, or preferences. You can also call recall_memories "
                        "to get the latest version at any time."
                    )
                    logger.info("Injected %d memories into system prompt for user=%s",
                                len(memory_lines), user_id)
        except Exception as mem_err:
            logger.warning("Failed to load memories for prompt injection: %s", mem_err)

    # ── Inject previous session context for conversation continuity ───
    if prior_context:
        prompt += (
            "\n\nPREVIOUS SESSION CONTEXT (the user is resuming this conversation):\n"
            + prior_context
            + "\n\nContinue naturally where this conversation left off. "
            "Reference relevant points from the previous session when helpful. "
            "Greet the user warmly and acknowledge you remember the previous conversation."
        )
        logger.info("Injected prior session context for user=%s", user_id)

    # Validate voice name against known Gemini voices
    valid_voices = {"Aoede", "Puck", "Charon", "Kore", "Fenrir", "Leda"}
    voice_name = voice if voice in valid_voices else "Aoede"

    declarations = get_tool_declarations(mode)
    config = types.LiveConnectConfig(
        system_instruction=types.Content(
            parts=[types.Part(text=prompt)],
        ),
        tools=[types.Tool(function_declarations=declarations)],
        response_modalities=["AUDIO"],
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(
                    voice_name=voice_name,
                ),
            ),
        ),
        # Explicitly declare the input audio format so Gemini VAD works correctly.
        # The Flutter client streams PCM 16-bit mono at 16 kHz.
        realtime_input_config=types.RealtimeInputConfig(
            automatic_activity_detection=types.AutomaticActivityDetection(
                disabled=False,
                start_of_speech_sensitivity=types.StartSensitivity.START_SENSITIVITY_HIGH,
                end_of_speech_sensitivity=types.EndSensitivity.END_SENSITIVITY_HIGH,
                prefix_padding_ms=100,
                silence_duration_ms=300,
            )
        ),
        input_audio_transcription=types.AudioTranscriptionConfig(),
        output_audio_transcription=types.AudioTranscriptionConfig(),
    )
    live_ctx = genai_client.aio.live.connect(
        model=settings.gemini_model,
        config=config,
    )
    session = await live_ctx.__aenter__()
    return live_ctx, session


# ── WebSocket endpoint ───────────────────────────────────────────────────────

@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    # ── Authenticate ──────────────────────────────────────────────────
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4401, reason="Missing auth token")
        return
    try:
        decoded = fb_auth.verify_id_token(token)
        if decoded.get("uid") != user_id:
            await websocket.close(code=4403, reason="UID mismatch")
            return
    except Exception as exc:
        logger.warning("Token verification failed for %s: %s", user_id, exc)
        await websocket.close(code=4401, reason="Invalid token")
        return

    await websocket.accept()
    session_id = str(uuid.uuid4())
    logger.info("Client connected: user=%s session=%s", user_id, session_id)

    # Mutable session state
    current_mode: str = AgentMode.GENERAL
    source_lang: str = "auto"
    target_lang: str = "en"
    current_voice: str = "Aoede"
    conversation_transcript: list[str] = []  # accumulate user speech for summary

    session_record = SessionRecord(
        session_id=session_id,
        user_id=user_id,
        title="Live Session",
        mode=current_mode,
    )

    cancel_event = asyncio.Event()
    # Guard: set while a mode/language switch is in progress so audio/video
    # forwarders pause instead of sending to a closed session.
    _switching = asyncio.Event()
    tracer = LatencyTracer(session_id)
    input_q = InputQueue()
    frame_throttle = FrameThrottle(min_interval=0.30)

    # Track last user audio timestamp for ambient nudge timing.
    _last_audio_time: float = time.monotonic()

    # ── Gemini session is lazy ─────────────────────────────────────────────
    # Defer Gemini connection until the client sends the first set_mode
    # (triggered by startSession / mic tap). This keeps the WebSocket alive
    # even if Gemini is temporarily unavailable, preventing the
    # connecting ↔ reconnecting loop the client would otherwise see.
    session = None
    live_ctx = None
    await _send_json(websocket, OutboundMessage(type=OutboundType.STATUS, text="connected"))

    # ── Reconnect helper (for mode switches) ──────────────────────────────
    async def _reconnect_session(new_mode: str, sl: str, tl: str, voice: str = "Aoede", prior_context: str | None = None):
        nonlocal live_ctx, session, current_mode, source_lang, target_lang, current_voice
        # Signal receiver BEFORE closing so it recognises this is a mode
        # switch rather than an unexpected error.
        _mode_switch_event.set()
        # Signal forwarders to pause so they don't send to the dead session.
        _switching.set()
        try:
            current_mode = new_mode
            source_lang = sl
            target_lang = tl
            current_voice = voice
            session_record.mode = new_mode
            session_record.source_lang = sl
            session_record.target_lang = tl
            # Close old (if exists — None on first call)
            if live_ctx:
                try:
                    await live_ctx.__aexit__(None, None, None)
                except Exception as exc:
                    logger.debug("Error closing old Gemini context: %s", exc)
            # Open new
            live_ctx, session = await _connect_gemini(new_mode, sl, tl, voice, user_id=user_id, prior_context=prior_context)
            logger.info("Reconnected Gemini in mode=%s voice=%s", new_mode, voice)
        finally:
            # Always release forwarders, even on failure, to prevent
            # permanently blocking the audio/video pipeline.
            _switching.clear()

    # ── Client → Gemini ───────────────────────────────────────────────────

    client_audio_count = 0
    # Asyncio Event that signals receive_from_gemini to restart its listen
    # loop immediately after a mode switch rather than sleeping.
    _mode_switch_event = asyncio.Event()

    # ── Audio forwarder (drains audio queue → Gemini at max speed) ─────

    async def _audio_forwarder() -> None:
        """Dedicated coroutine that drains the audio queue → Gemini.

        By running in its own task, audio forwarding is NEVER blocked by
        video encoding, rate-limit checks, or mode-switch reconnects.
        """
        nonlocal client_audio_count, _last_audio_time
        while not cancel_event.is_set():
            try:
                audio_bytes = await asyncio.wait_for(
                    input_q._audio_q.get(), timeout=1.0,
                )
            except asyncio.TimeoutError:
                continue
            except Exception:
                break

            client_audio_count += 1
            _last_audio_time = time.monotonic()
            # Pause while a mode switch is in progress to avoid sending
            # to a closed session.
            if _switching.is_set() or session is None:
                continue
            tracer.start("audio_send")
            if client_audio_count % 50 == 1:
                logger.info("Client audio chunk #%d (%d bytes) → Gemini",
                            client_audio_count, len(audio_bytes))
            try:
                try:
                    await session.send_realtime_input(
                        audio=types.Blob(data=audio_bytes, mime_type="audio/pcm;rate=16000"),
                    )
                except TypeError:
                    await session.send_realtime_input(
                        media=types.Blob(data=audio_bytes, mime_type="audio/pcm;rate=16000"),
                    )
            except Exception as exc:
                logger.debug("Audio send failed: %s", exc)
            tracer.end("audio_send")

    # ── Video forwarder (latest-wins frame slot → Gemini) ──────────────

    async def _video_forwarder() -> None:
        """Sends the latest video frame to Gemini, throttled to avoid
        flooding the Live session with high-FPS imagery."""
        while not cancel_event.is_set():
            try:
                frame_data = await asyncio.wait_for(
                    input_q.get_video(), timeout=2.0,
                )
            except asyncio.TimeoutError:
                continue
            except Exception:
                break
            if frame_data is None:
                continue
            if not frame_throttle.should_send():
                continue
            if _switching.is_set() or session is None:
                continue
            tracer.start("frame_send")
            try:
                await session.send_realtime_input(
                    media=types.Blob(data=frame_data, mime_type="image/jpeg"),
                )
            except Exception as exc:
                logger.debug("Video frame send failed: %s", exc)
            tracer.end("frame_send")

    # ── Client → queue router ──────────────────────────────────────────

    async def receive_from_client() -> None:
        nonlocal current_mode, source_lang, target_lang
        msg_count = 0
        RATE_LIMIT = 60
        RATE_WINDOW = 10.0
        rate_timestamps: list[float] = []
        try:
            while not cancel_event.is_set():
                raw = await websocket.receive_text()
                tracer.start("ws_parse")
                msg = InboundMessage.model_validate_json(raw)
                tracer.end("ws_parse")
                msg_count += 1

                # Measure client→backend latency from the embedded timestamp.
                if msg.timestamp:
                    client_ts = msg.timestamp
                    server_ts = time.time()
                    hop_ms = (server_ts - client_ts) * 1000
                    if hop_ms > 0:
                        tracer.record("client_hop", min(hop_ms, 5000))  # cap outliers

                # Rate-limit non-audio messages
                if msg.type != InboundType.AUDIO:
                    now = asyncio.get_event_loop().time()
                    rate_timestamps.append(now)
                    cutoff = now - RATE_WINDOW
                    rate_timestamps[:] = [t for t in rate_timestamps if t > cutoff]
                    if len(rate_timestamps) > RATE_LIMIT:
                        logger.warning("Rate limit exceeded for user=%s (%d msgs in %.0fs)",
                                       user_id, len(rate_timestamps), RATE_WINDOW)
                        await _send_json(websocket, OutboundMessage(
                            type=OutboundType.ERROR,
                            text="Too many messages. Please slow down.",
                        ))
                        continue

                if msg.type != InboundType.PING and msg.type != InboundType.AUDIO:
                    logger.info("WS msg #%d type=%s", msg_count, msg.type)
                elif msg.type == InboundType.PING and msg_count % 5 == 0:
                    logger.info("WS msg #%d type=ping (periodic)", msg_count)

                if msg.type == InboundType.PING:
                    await _send_json(websocket, OutboundMessage(type=OutboundType.PONG))
                    continue

                # Mode switching
                if msg.type == InboundType.SET_MODE and msg.mode:
                    voice = msg.voice or current_voice

                    # ── Conversation continuity: load prior session context ──
                    prior_context: str | None = None
                    if msg.resume_session_id and db:
                        try:
                            session_doc = await asyncio.to_thread(
                                db.collection("users").document(user_id)
                                .collection("sessions").document(msg.resume_session_id).get
                            )
                            if session_doc.exists:
                                sd = session_doc.to_dict()
                                prior_context = (
                                    f"Session title: {sd.get('title', 'Unknown')}\n"
                                    f"Mode: {sd.get('mode', 'general')}\n"
                                    f"Summary: {sd.get('summary', 'No summary available')}\n"
                                    f"Topics discussed: {', '.join(sd.get('topics', []))}\n"
                                    f"Number of conversation turns: {sd.get('turn_count', 0)}"
                                )
                                logger.info("Resuming session %s for user %s",
                                            msg.resume_session_id, user_id)
                        except Exception as resume_err:
                            logger.warning("Failed to load resume session: %s", resume_err)

                    if session is not None and msg.mode == current_mode and voice == current_voice and not prior_context:
                        await _send_json(websocket, OutboundMessage(
                            type=OutboundType.MODE_CHANGED,
                            text=msg.mode,
                            payload={"mode": msg.mode},
                        ))
                        continue
                    try:
                        tracer.start("mode_switch")
                        # Flush the input queue so stale audio from the old
                        # mode doesn't contaminate the new session.
                        input_q.flush()
                        await _reconnect_session(msg.mode, source_lang, target_lang, voice, prior_context=prior_context)
                        # _mode_switch_event is now set inside _reconnect_session
                        ms = tracer.end("mode_switch")
                        logger.info("Mode switch completed in %.0fms", ms)
                        await _send_json(websocket, OutboundMessage(
                            type=OutboundType.MODE_CHANGED,
                            text=msg.mode,
                            payload={"mode": msg.mode},
                        ))
                    except Exception as exc:
                        tracer.end("mode_switch")
                        logger.error("Mode switch failed: %s", exc)
                        await _send_json(websocket, OutboundMessage(
                            type=OutboundType.ERROR,
                            text=f"Mode switch failed: {exc}",
                        ))
                    continue

                # Language switching (translator)
                if msg.type == InboundType.SET_LANGUAGE:
                    sl = msg.source_lang or source_lang
                    tl = msg.target_lang or target_lang
                    if sl == source_lang and tl == target_lang:
                        continue
                    try:
                        await _reconnect_session(current_mode, sl, tl, current_voice)
                        await _send_json(websocket, OutboundMessage(
                            type=OutboundType.STATUS,
                            text=f"language:{sl}→{tl}",
                        ))
                    except Exception as exc:
                        logger.error("Language switch failed: %s", exc)
                    continue

                # ── Media → queue (never blocks on Gemini send) ────────
                if msg.type == InboundType.AUDIO and msg.data:
                    audio_bytes = base64.b64decode(msg.data)
                    await input_q.put_audio(audio_bytes)
                elif msg.type == InboundType.VIDEO and msg.data:
                    image_bytes = base64.b64decode(msg.data)
                    input_q.put_video(image_bytes)
                elif msg.type == InboundType.TEXT and msg.text:
                    if session is not None:
                        await session.send_client_content(
                            turns=types.Content(
                                role="user",
                                parts=[types.Part(text=msg.text)],
                            ),
                            turn_complete=True,
                        )
                elif msg.type == InboundType.END_TURN:
                    if session is not None:
                        await session.send_client_content(turns=None, turn_complete=True)

                # ── Explicit session save (client tapped Stop) ─────────
                elif msg.type == InboundType.END_SESSION:
                    session_record.ended_at = datetime.now(timezone.utc).timestamp()
                    # Auto-title based on mode
                    mode_titles = {
                        AgentMode.TRANSLATOR: "Translation Session",
                        AgentMode.TUTOR: "Tutoring Session",
                        AgentMode.SUPPORT: "Support Session",
                    }
                    if session_record.title == "Live Session":
                        session_record.title = mode_titles.get(current_mode, "Live Session")

                    # Generate AI summary
                    if conversation_transcript and len(conversation_transcript) >= 2:
                        try:
                            transcript_text = "\n".join(conversation_transcript[-50:])
                            summary_prompt = (
                                "Summarize this voice conversation in 1-2 concise sentences. "
                                "Focus on key topics discussed and any decisions or outcomes. "
                                "Do NOT use quotes or say 'the user said'. Just state what was "
                                "discussed.\n\n"
                                f"Mode: {current_mode}\n"
                                f"Conversation transcript:\n{transcript_text}"
                            )
                            summary_response = await genai_client.aio.models.generate_content(
                                model="gemini-2.0-flash-lite",
                                contents=summary_prompt,
                            )
                            if summary_response.text:
                                session_record.summary = summary_response.text.strip()
                                logger.info("AI summary: %s", session_record.summary[:100])
                        except Exception as summary_err:
                            logger.warning("Summary generation failed: %s", summary_err)

                    await _save_session(user_id, session_record)
                    await _send_json(websocket, OutboundMessage(
                        type=OutboundType.SESSION_SAVED,
                        text="session_saved",
                        payload={"session_id": session_record.session_id},
                    ))
                    logger.info("Session explicitly saved: %s (turns=%d)",
                                session_record.session_id, session_record.turn_count)

                    # Reset for next session on the same WS connection
                    session_record = SessionRecord(
                        session_id=str(uuid.uuid4()),
                        user_id=user_id,
                        title="Live Session",
                        mode=current_mode,
                    )
                    conversation_transcript.clear()
                    continue

        except WebSocketDisconnect:
            logger.info("Client disconnected: user=%s", user_id)
        except Exception as exc:
            logger.error("receive_from_client error: %s", exc)
        finally:
            cancel_event.set()

    # ── Gemini → Client ───────────────────────────────────────────────────

    async def receive_from_gemini() -> None:
        nonlocal session, live_ctx
        max_inner_retries = 5
        inner_retry_count = 0
        try:
            while not cancel_event.is_set():
                # Wait for Gemini session to be established (lazy connect).
                if session is None:
                    try:
                        await asyncio.wait_for(_mode_switch_event.wait(), timeout=1.0)
                        _mode_switch_event.clear()
                    except asyncio.TimeoutError:
                        pass
                    continue
                try:
                    logger.info("Waiting for next Gemini turn... (client_audio_count=%d)", client_audio_count)
                    turn = session.receive()
                    inner_retry_count = 0
                    tracer.start("gemini_first_token")
                    first_token_traced = False
                    tracer.start("gemini_turn")
                    async for response in turn:
                        # Model audio / text
                        if response.server_content is not None:
                            sc = response.server_content
                            if sc.model_turn and sc.model_turn.parts:
                                for part in sc.model_turn.parts:
                                    if part.inline_data and part.inline_data.data:
                                        if not first_token_traced:
                                            tracer.end("gemini_first_token")
                                            first_token_traced = True
                                        tracer.start("audio_out")
                                        audio_b64 = base64.b64encode(part.inline_data.data).decode("ascii")
                                        logger.info("Audio chunk → client: %d bytes", len(part.inline_data.data))
                                        await _send_json(websocket, OutboundMessage(
                                            type=OutboundType.AUDIO, data=audio_b64,
                                        ))
                                        tracer.end("audio_out")
                                    elif part.text:
                                        # For native-audio models the text parts are internal
                                        # "thinking" fragments — do NOT surface them as
                                        # transcript to the client.
                                        logger.debug("model_turn text (suppressed): %s", part.text[:80])
                            # Send user speech transcription as a distinct type
                            # so the client can show "You said: …" separately.
                            if sc.input_transcription:
                                txt = getattr(sc.input_transcription, 'text', None)
                                if txt:
                                    conversation_transcript.append(txt)
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.USER_TRANSCRIPT, text=txt,
                                    ))
                            # Forward AI output transcription so the client can
                            # display what the AI said as text.
                            if sc.output_transcription:
                                txt = getattr(sc.output_transcription, 'text', None)
                                if txt:
                                    conversation_transcript.append(f"AI: {txt}")
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.TRANSCRIPT, text=txt,
                                    ))
                            if sc.turn_complete:
                                turn_ms = tracer.end("gemini_turn")
                                if not first_token_traced:
                                    tracer.end("gemini_first_token")
                                session_record.turn_count += 1
                                logger.info(">>> turn_complete (%.0fms, audio_in=%d, turns=%d)",
                                            turn_ms, client_audio_count, session_record.turn_count)
                                await _send_json(websocket, OutboundMessage(type=OutboundType.TURN_COMPLETE))
                            if sc.interrupted:
                                tracer.end("gemini_turn")
                                if not first_token_traced:
                                    tracer.end("gemini_first_token")
                                # Flush the input queue on barge-in so stale
                                # buffered audio doesn't play into the new turn.
                                input_q.flush()
                                logger.info(">>> interrupted from Gemini — flushing queue")
                                await _send_json(websocket, OutboundMessage(type=OutboundType.INTERRUPTED))

                        # Tool / function calls
                        if response.tool_call is not None:
                            fn_responses: list[types.FunctionResponse] = []
                            for fc in response.tool_call.function_calls:
                                logger.info("Function call: %s(%s)", fc.name, fc.args)
                                tracer.start("tool_dispatch")
                                result_json = await dispatch_tool_call(
                                    fc.name, fc.args or {}, db=db, user_id=user_id,
                                )
                                tool_ms = tracer.end("tool_dispatch")
                                if tool_ms > 200:
                                    logger.warning("Slow tool dispatch: %s took %.0fms", fc.name, tool_ms)

                                # Route tool results to the correct outbound type
                                if fc.name == "create_ui_action":
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.UI_ACTION,
                                        action_type=fc.args.get("action_type", "generic"),
                                        payload={
                                            "title": fc.args.get("title", ""),
                                            "description": fc.args.get("description", ""),
                                            "icon": fc.args.get("icon", "auto_awesome"),
                                            "primary_action_label": fc.args.get("primary_action_label", "OK"),
                                        },
                                    ))

                                elif fc.name == "live_translate":
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.TRANSLATION,
                                        payload={
                                            "source_text": fc.args.get("source_text", ""),
                                            "translated_text": fc.args.get("translated_text", ""),
                                            "source_language": fc.args.get("source_language", "auto"),
                                            "target_language": fc.args.get("target_language", "en"),
                                            "formality": fc.args.get("formality", "neutral"),
                                        },
                                    ))

                                elif fc.name == "translation_card":
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.UI_ACTION,
                                        action_type="translation_card",
                                        payload={
                                            "title": "Translation",
                                            "description": f"{fc.args.get('original', '')} → {fc.args.get('translated', '')}",
                                            "original": fc.args.get("original", ""),
                                            "translated": fc.args.get("translated", ""),
                                            "source_lang": fc.args.get("source_lang", ""),
                                            "target_lang": fc.args.get("target_lang", ""),
                                            "icon": "translate",
                                            "primary_action_label": "Save",
                                        },
                                    ))

                                elif fc.name in ("provide_hint", "grade_step", "tutor_card"):
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.TUTOR_STEP,
                                        payload={"tool": fc.name, **(fc.args or {})},
                                    ))

                                elif fc.name == "analyze_homework":
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.TUTOR_STEP,
                                        payload={
                                            "tool": "analyze_homework",
                                            "subject": fc.args.get("subject", ""),
                                            "description": fc.args.get("description", ""),
                                            "difficulty": fc.args.get("difficulty", "medium"),
                                        },
                                    ))

                                elif fc.name == "solve_problem":
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.TUTOR_STEP,
                                        payload={
                                            "tool": "solve_problem",
                                            "subject": fc.args.get("subject", ""),
                                            "problem": fc.args.get("problem", ""),
                                            "solution_steps": fc.args.get("solution_steps", []),
                                            "final_answer": fc.args.get("final_answer", ""),
                                            "explanation": fc.args.get("explanation", ""),
                                        },
                                    ))

                                elif fc.name == "explain_concept":
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.TUTOR_STEP,
                                        payload={
                                            "tool": "explain_concept",
                                            "concept": fc.args.get("concept", ""),
                                            "subject": fc.args.get("subject", ""),
                                            "explanation": fc.args.get("explanation", ""),
                                            "examples": fc.args.get("examples", []),
                                            "related_topics": fc.args.get("related_topics", []),
                                            "difficulty_level": fc.args.get("difficulty_level", "intermediate"),
                                        },
                                    ))

                                elif fc.name == "export_document":
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.EXPORT,
                                        payload={
                                            "tool": "export_document",
                                            "title": fc.args.get("title", "Export"),
                                            "content": fc.args.get("content", ""),
                                            "format": fc.args.get("format", "pdf"),
                                            "sections": fc.args.get("sections", []),
                                        },
                                    ))

                                elif fc.name == "switch_topic":
                                    topic = fc.args.get("new_topic", "")
                                    session_record.topics.append(topic)
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.SUPPORT_TOPIC,
                                        payload={"new_topic": topic, "reason": fc.args.get("reason", "")},
                                    ))

                                elif fc.name in ("escalate_case", "log_resolution", "support_card"):
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.UI_ACTION,
                                        action_type=fc.name,
                                        payload=fc.args or {},
                                    ))

                                fn_responses.append(
                                    types.FunctionResponse(
                                        name=fc.name,
                                        response={"result": result_json},
                                        id=fc.id,
                                    )
                                )
                            await session.send_tool_response(
                                function_responses=fn_responses,
                            )

                except Exception as inner_exc:
                    if cancel_event.is_set():
                        break
                    # If a mode switch just happened, the old session was
                    # intentionally torn down — treat it as expected and
                    # immediately re-attach to the new session.
                    if _mode_switch_event.is_set():
                        _mode_switch_event.clear()
                        inner_retry_count = 0
                        logger.info("Mode switch detected — re-attaching to new Gemini session")
                        continue
                    inner_retry_count += 1
                    logger.error("Gemini receive error (%d/%d): %s",
                                 inner_retry_count, max_inner_retries, inner_exc)
                    if inner_retry_count >= max_inner_retries:
                        # Reset Gemini session but keep WebSocket alive.
                        # Auto-retry connection before falling back to idle.
                        logger.error("Max Gemini retries — auto-reconnecting (WS stays alive)")
                        session = None
                        inner_retry_count = 0
                        await _send_json(websocket, OutboundMessage(
                            type=OutboundType.STATUS,
                            text="reconnecting",
                        ))
                        for _retry in range(3):
                            await asyncio.sleep(2 * (_retry + 1))
                            if cancel_event.is_set():
                                return
                            try:
                                await _reconnect_session(
                                    current_mode, source_lang, target_lang, current_voice,
                                )
                                logger.info("Auto-reconnected Gemini (attempt %d/3)", _retry + 1)
                                await _send_json(websocket, OutboundMessage(
                                    type=OutboundType.STATUS, text="connected",
                                ))
                                break
                            except Exception as retry_exc:
                                logger.warning("Auto-reconnect %d/3 failed: %s", _retry + 1, retry_exc)
                        else:
                            # All auto-retries failed — go back to waiting
                            await _send_json(websocket, OutboundMessage(
                                type=OutboundType.ERROR,
                                text="AI unavailable — tap mic to retry",
                            ))
                        continue
                    await asyncio.sleep(0.5 * inner_retry_count)
        except Exception as exc:
            logger.error("receive_from_gemini fatal: %s", exc)
        # NOTE: Do NOT set cancel_event here. Only receive_from_client
        # should tear down the WS when the client actually disconnects.
        # Gemini failures are recoverable and should not kill the WS.

    # ── Heartbeat ─────────────────────────────────────────────────────────

    async def heartbeat() -> None:
        while not cancel_event.is_set():
            await asyncio.sleep(settings.ws_heartbeat_interval)
            try:
                await _send_json(websocket, OutboundMessage(type=OutboundType.PONG, text="heartbeat"))
            except Exception:
                cancel_event.set()

    # ── Proactive ambient nudge (vision-triggered insights) ───────────────

    async def _ambient_nudge() -> None:
        """Periodically nudge Gemini to proactively comment on the camera view.

        Triggers ONLY when:
          1. Video frames are actively flowing (camera is on)
          2. No user audio has been received for ≥15 seconds (user is silent)
          3. At least 30 seconds since the last nudge (avoid spam)
          4. Mode is general or tutor (vision-relevant modes)
        """
        last_nudge_time = 0.0
        nudge_interval = 30.0    # min seconds between nudges
        silence_threshold = 15.0  # seconds of silence before nudging
        while not cancel_event.is_set():
            await asyncio.sleep(5.0)
            if session is None or _switching.is_set():
                continue
            if current_mode not in (AgentMode.GENERAL, AgentMode.TUTOR):
                continue
            now = time.monotonic()
            # Check that video is actively flowing
            if now - frame_throttle.last_sent_time > 5.0:
                continue  # No recent video frames — camera is off
            # Check user silence duration
            if now - _last_audio_time < silence_threshold:
                continue  # User spoke recently
            # Rate-limit nudges
            if now - last_nudge_time < nudge_interval:
                continue
            try:
                await session.send_client_content(
                    turns=types.Content(
                        role="user",
                        parts=[types.Part(text="[AMBIENT]")],
                    ),
                    turn_complete=True,
                )
                last_nudge_time = now
                logger.info("Ambient nudge sent (silence=%.0fs)", now - _last_audio_time)
            except Exception as exc:
                logger.debug("Ambient nudge failed: %s", exc)

    # ── Run all ───────────────────────────────────────────────────────────

    try:
        await asyncio.gather(
            receive_from_client(),
            _audio_forwarder(),
            _video_forwarder(),
            receive_from_gemini(),
            heartbeat(),
            _ambient_nudge(),
            return_exceptions=True,
        )
    finally:
        session_record.ended_at = datetime.now(timezone.utc).timestamp()
        # Auto-title based on mode
        mode_titles = {
            AgentMode.TRANSLATOR: "Translation Session",
            AgentMode.TUTOR: "Tutoring Session",
            AgentMode.SUPPORT: "Support Session",
        }
        if session_record.title == "Live Session":
            session_record.title = mode_titles.get(current_mode, "Live Session")

        # ── Generate AI summary from conversation transcript ──────────
        if conversation_transcript and len(conversation_transcript) >= 2:
            try:
                transcript_text = "\n".join(conversation_transcript[-50:])  # last 50 utterances
                summary_prompt = (
                    "Summarize this voice conversation in 1-2 concise sentences. "
                    "Focus on key topics discussed and any decisions or outcomes. "
                    "Do NOT use quotes or say 'the user said'. Just state what was "
                    "discussed.\n\n"
                    f"Mode: {current_mode}\n"
                    f"Conversation transcript:\n{transcript_text}"
                )
                summary_response = await genai_client.aio.models.generate_content(
                    model="gemini-2.0-flash-lite",
                    contents=summary_prompt,
                )
                if summary_response.text:
                    session_record.summary = summary_response.text.strip()
                    logger.info("AI summary generated: %s", session_record.summary[:100])
            except Exception as summary_err:
                logger.warning("Failed to generate session summary: %s", summary_err)

        # Log final latency summary
        latency_summary = tracer.summary()
        if latency_summary:
            logger.info("LATENCY FINAL[%s]: %s", session_id[:8], latency_summary)
        if frame_throttle.dropped > 0:
            logger.info("Dropped %d redundant video frames", frame_throttle.dropped)

        # Only save on WS teardown if there are unsaved turns (end_session
        # may have already saved the current session mid-connection).
        if session_record.turn_count > 0:
            await _save_session(user_id, session_record)
        if live_ctx is not None:
            try:
                await live_ctx.__aexit__(None, None, None)
            except Exception as exc:
                logger.debug("Error closing Gemini context on teardown: %s", exc)
        try:
            await websocket.close()
        except Exception as exc:
            logger.debug("Error closing websocket on teardown: %s", exc)
        logger.info("Session ended: user=%s session=%s mode=%s turns=%d",
                     user_id, session_id, current_mode, session_record.turn_count)
