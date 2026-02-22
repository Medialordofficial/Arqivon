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
from datetime import datetime
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware

import firebase_admin
from firebase_admin import credentials, firestore as fb_firestore, storage

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
logger = logging.getLogger("arqivo")

# ── Globals ───────────────────────────────────────────────────────────────────

db: Any = None
gcs_bucket: Any = None
genai_client: genai.Client | None = None


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
        "upsert_firestore_memory to persist it across sessions.\n\n"

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
        "You provide live, broadcast-quality translation across 100+ languages with native "
        "fluency, cultural awareness, and context sensitivity.\n\n"

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
        "http://localhost",
        "http://localhost:8080",
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
        "timestamp": datetime.utcnow().isoformat(),
    }


@app.get("/api/sessions/{user_id}")
async def list_sessions(user_id: str):
    if db is None:
        raise HTTPException(503, "Firestore unavailable")
    docs = (
        db.collection("users")
        .document(user_id)
        .collection("sessions")
        .order_by("started_at", direction=fb_firestore.Query.DESCENDING)
        .limit(50)
        .stream()
    )
    return [doc.to_dict() | {"id": doc.id} for doc in docs]


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _send_json(ws: WebSocket, msg: OutboundMessage) -> None:
    try:
        await ws.send_text(msg.model_dump_json())
    except Exception:
        pass


async def _save_session(user_id: str, record: SessionRecord) -> None:
    if db is None:
        return
    try:
        (
            db.collection("users")
            .document(user_id)
            .collection("sessions")
            .document(record.session_id)
            .set(record.model_dump(), merge=True)
        )
        logger.info("Session %s saved for user %s", record.session_id, user_id)
    except Exception as exc:
        logger.error("Failed to save session: %s", exc)


def _backoff(attempt: int, base: float = 0.5, cap: float = 30.0) -> float:
    delay = min(base * (2 ** attempt), cap)
    return delay + random.uniform(0, delay * 0.1)


async def _connect_gemini(mode: str, source_lang: str, target_lang: str):
    """Build a LiveConnectConfig for the given mode and open a session."""
    prompt = SYSTEM_PROMPTS.get(mode, SYSTEM_PROMPTS[AgentMode.GENERAL])
    # Inject language context for translator mode
    if mode == AgentMode.TRANSLATOR:
        prompt += (
            f"\nThe user's source language is '{source_lang}' "
            f"(auto means detect automatically). "
            f"The target translation language is '{target_lang}'."
        )

    declarations = get_tool_declarations(mode)
    config = types.LiveConnectConfig(
        system_instruction=prompt,
        tools=[types.Tool(function_declarations=declarations)],
        response_modalities=["AUDIO"],
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(
                    voice_name="Aoede",
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
                prefix_padding_ms=300,
                silence_duration_ms=800,
            )
        ),
        input_audio_transcription=types.AudioTranscriptionConfig(),
        # NOTE: output_audio_transcription intentionally omitted — AI audio is
        # already played to the user; transcribing it back as text causes
        # haphazard text in random languages to appear on the client.
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
    await websocket.accept()
    session_id = str(uuid.uuid4())
    logger.info("Client connected: user=%s session=%s", user_id, session_id)

    # Mutable session state
    current_mode: str = AgentMode.GENERAL
    source_lang: str = "auto"
    target_lang: str = "en"

    session_record = SessionRecord(
        session_id=session_id,
        user_id=user_id,
        title="Live Session",
        mode=current_mode,
    )

    cancel_event = asyncio.Event()

    # ── Connect to Gemini Live API with retry ─────────────────────────────
    attempt = 0
    session = None
    live_ctx = None

    while attempt < settings.ws_max_reconnect_attempts and not cancel_event.is_set():
        try:
            live_ctx, session = await _connect_gemini(current_mode, source_lang, target_lang)
            logger.info("Gemini session established mode=%s (attempt %d)", current_mode, attempt + 1)
            await _send_json(websocket, OutboundMessage(type=OutboundType.STATUS, text="connected"))
            break
        except Exception as exc:
            attempt += 1
            delay = _backoff(attempt)
            logger.warning("Gemini connect %d/%d failed: %s – retry %.1fs",
                           attempt, settings.ws_max_reconnect_attempts, exc, delay)
            await _send_json(websocket, OutboundMessage(
                type=OutboundType.STATUS, text=f"reconnecting ({attempt})",
            ))
            await asyncio.sleep(delay)

    if session is None:
        await _send_json(websocket, OutboundMessage(
            type=OutboundType.ERROR, text="Failed to connect to AI after retries",
        ))
        await websocket.close()
        return

    # ── Reconnect helper (for mode switches) ──────────────────────────────
    async def _reconnect_session(new_mode: str, sl: str, tl: str):
        nonlocal live_ctx, session, current_mode, source_lang, target_lang
        current_mode = new_mode
        source_lang = sl
        target_lang = tl
        session_record.mode = new_mode
        session_record.source_lang = sl
        session_record.target_lang = tl
        # Close old
        if live_ctx:
            try:
                await live_ctx.__aexit__(None, None, None)
            except Exception:
                pass
        # Open new
        live_ctx, session = await _connect_gemini(new_mode, sl, tl)
        logger.info("Reconnected Gemini in mode=%s", new_mode)

    # ── Client → Gemini ───────────────────────────────────────────────────

    client_audio_count = 0

    async def receive_from_client() -> None:
        nonlocal current_mode, source_lang, target_lang, client_audio_count
        msg_count = 0
        try:
            while not cancel_event.is_set():
                raw = await websocket.receive_text()
                msg = InboundMessage.model_validate_json(raw)
                msg_count += 1
                # Log every message type so we can diagnose silent drops
                if msg.type != InboundType.PING and msg.type != InboundType.AUDIO:
                    logger.info("WS msg #%d type=%s", msg_count, msg.type)
                elif msg.type == InboundType.PING and msg_count % 5 == 0:
                    logger.info("WS msg #%d type=ping (periodic)", msg_count)

                if msg.type == InboundType.PING:
                    await _send_json(websocket, OutboundMessage(type=OutboundType.PONG))
                    continue

                # Mode switching
                if msg.type == InboundType.SET_MODE and msg.mode:
                    if msg.mode == current_mode:
                        # Already in this mode — just acknowledge, no reconnect needed.
                        await _send_json(websocket, OutboundMessage(
                            type=OutboundType.MODE_CHANGED,
                            text=msg.mode,
                            payload={"mode": msg.mode},
                        ))
                        continue
                    try:
                        await _reconnect_session(msg.mode, source_lang, target_lang)
                        await _send_json(websocket, OutboundMessage(
                            type=OutboundType.MODE_CHANGED,
                            text=msg.mode,
                            payload={"mode": msg.mode},
                        ))
                    except Exception as exc:
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
                        # No change — skip reconnect.
                        continue
                    try:
                        await _reconnect_session(current_mode, sl, tl)
                        await _send_json(websocket, OutboundMessage(
                            type=OutboundType.STATUS,
                            text=f"language:{sl}→{tl}",
                        ))
                    except Exception as exc:
                        logger.error("Language switch failed: %s", exc)
                    continue

                # Media
                if msg.type == InboundType.AUDIO and msg.data:
                    audio_bytes = base64.b64decode(msg.data)
                    client_audio_count += 1
                    if client_audio_count % 50 == 1:
                        logger.info("Client audio chunk #%d (%d bytes) → Gemini", client_audio_count, len(audio_bytes))
                    await session.send_realtime_input(
                        media=types.Blob(data=audio_bytes, mime_type="audio/pcm;rate=16000"),
                    )
                elif msg.type == InboundType.VIDEO and msg.data:
                    image_bytes = base64.b64decode(msg.data)
                    await session.send_realtime_input(
                        media=types.Blob(data=image_bytes, mime_type="image/jpeg"),
                    )
                elif msg.type == InboundType.TEXT and msg.text:
                    await session.send_client_content(
                        turns=types.Content(
                            role="user",
                            parts=[types.Part(text=msg.text)],
                        ),
                        turn_complete=True,
                    )
                    session_record.turn_count += 1
                elif msg.type == InboundType.END_TURN:
                    await session.send_client_content(turns=None, turn_complete=True)

        except WebSocketDisconnect:
            logger.info("Client disconnected: user=%s", user_id)
        except Exception as exc:
            logger.error("receive_from_client error: %s", exc)
        finally:
            cancel_event.set()

    # ── Gemini → Client ───────────────────────────────────────────────────

    async def receive_from_gemini() -> None:
        try:
            while not cancel_event.is_set():
                try:
                    logger.info("Waiting for next Gemini turn... (client_audio_count=%d)", client_audio_count)
                    turn = session.receive()
                    async for response in turn:
                        # Model audio / text
                        if response.server_content is not None:
                            sc = response.server_content
                            if sc.model_turn and sc.model_turn.parts:
                                for part in sc.model_turn.parts:
                                    if part.inline_data and part.inline_data.data:
                                        audio_b64 = base64.b64encode(part.inline_data.data).decode("ascii")
                                        logger.info("Audio chunk → client: %d bytes", len(part.inline_data.data))
                                        await _send_json(websocket, OutboundMessage(
                                            type=OutboundType.AUDIO, data=audio_b64,
                                        ))
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
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.USER_TRANSCRIPT, text=txt,
                                    ))
                            # output_transcription is intentionally ignored — see
                            # config comment above.
                            if sc.turn_complete:
                                logger.info(">>> turn_complete from Gemini — sending to client (audio_chunks_from_client=%d)", client_audio_count)
                                await _send_json(websocket, OutboundMessage(type=OutboundType.TURN_COMPLETE))
                            if sc.interrupted:
                                logger.info(">>> interrupted from Gemini — sending to client")
                                await _send_json(websocket, OutboundMessage(type=OutboundType.INTERRUPTED))

                        # Tool / function calls
                        if response.tool_call is not None:
                            fn_responses: list[types.FunctionResponse] = []
                            for fc in response.tool_call.function_calls:
                                logger.info("Function call: %s(%s)", fc.name, fc.args)
                                result_json = await dispatch_tool_call(
                                    fc.name, fc.args or {}, db=db, user_id=user_id,
                                )

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
                    logger.error("Gemini receive error: %s", inner_exc)
                    await asyncio.sleep(0.5)
        except Exception as exc:
            logger.error("receive_from_gemini fatal: %s", exc)
        finally:
            cancel_event.set()

    # ── Heartbeat ─────────────────────────────────────────────────────────

    async def heartbeat() -> None:
        while not cancel_event.is_set():
            await asyncio.sleep(settings.ws_heartbeat_interval)
            try:
                await _send_json(websocket, OutboundMessage(type=OutboundType.PONG, text="heartbeat"))
            except Exception:
                cancel_event.set()

    # ── Run all ───────────────────────────────────────────────────────────

    try:
        await asyncio.gather(
            receive_from_client(),
            receive_from_gemini(),
            heartbeat(),
            return_exceptions=True,
        )
    finally:
        session_record.ended_at = datetime.utcnow().timestamp()
        # Auto-title based on mode
        mode_titles = {
            AgentMode.TRANSLATOR: "Translation Session",
            AgentMode.TUTOR: "Tutoring Session",
            AgentMode.SUPPORT: "Support Session",
        }
        if session_record.title == "Live Session":
            session_record.title = mode_titles.get(current_mode, "Live Session")
        await _save_session(user_id, session_record)
        if live_ctx is not None:
            try:
                await live_ctx.__aexit__(None, None, None)
            except Exception:
                pass
        try:
            await websocket.close()
        except Exception:
            pass
        logger.info("Session ended: user=%s session=%s mode=%s turns=%d",
                     user_id, session_id, current_mode, session_record.turn_count)
