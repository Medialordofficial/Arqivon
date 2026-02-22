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
        "You are Arqivon, a helpful real-time multimodal AI assistant. "
        "You can see through the user's camera and hear their voice simultaneously. "
        "When you detect actionable items (phone numbers, addresses, calendar events, "
        "text to translate, QR codes, business cards), proactively call create_ui_action. "
        "When the user asks you to remember something, call upsert_firestore_memory. "
        "Be concise, friendly, and proactive. Speak naturally."
    ),
    AgentMode.TRANSLATOR: (
        "You are Arqivon Translator, a real-time multilingual translation assistant. "
        "Your PRIMARY job is to listen to the user speaking in one language and provide "
        "live translations using the live_translate tool so subtitles appear on screen. "
        "ALWAYS call live_translate with the source_text, detected source_language, and "
        "target_language for every meaningful utterance the user makes. "
        "Handle graceful interruptions: if the user speaks mid-translation, stop and "
        "translate the new input immediately. Detect language automatically when set to 'auto'. "
        "For important phrases, use translation_card to create a saveable flashcard. "
        "Speak the translated text aloud in the target language. "
        "Support formal/informal registers. Be natural and conversational."
    ),
    AgentMode.TUTOR: (
        "You are Arqivon Tutor, a vision-enabled smart tutoring assistant. "
        "The student shows you homework, diagrams, equations, or problems via camera. "
        "NEVER give the full answer immediately. Instead: "
        "1) Call analyze_homework to identify the subject and problem. "
        "2) Guide step-by-step using provide_hint — give hints, not answers. "
        "3) When the student attempts a step, call grade_step with feedback. "
        "4) Use tutor_card to render rich progress cards showing step X of Y. "
        "Handle interruptions gracefully: if the student asks about a different "
        "concept mid-explanation, acknowledge the pivot and adapt. "
        "Preserve context: remember what was discussed earlier in the session. "
        "Use the Socratic method. Be encouraging and patient. "
        "Related concepts should be woven into explanations naturally."
    ),
    AgentMode.SUPPORT: (
        "You are Arqivon Support, a voice-driven intelligent customer support agent. "
        "Maintain a natural, call-like conversation. "
        "Track topic changes using switch_topic when the customer shifts subjects. "
        "When you resolve an issue, call log_resolution with the outcome. "
        "If you cannot resolve, call escalate_case with severity and summary. "
        "Use support_card to render contextual options for the customer. "
        "Handle mid-conversation topic switching gracefully: acknowledge the change, "
        "briefly summarize what was discussed, and transition smoothly. "
        "Maintain a professional but warm tone. Reference previous context naturally. "
        "If the user says 'go back to…', resume the previous topic seamlessly."
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

    async def receive_from_client() -> None:
        nonlocal current_mode, source_lang, target_lang
        try:
            while not cancel_event.is_set():
                raw = await websocket.receive_text()
                msg = InboundMessage.model_validate_json(raw)

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
                    await session.send(
                        input=types.LiveClientRealtimeInput(
                            media_chunks=[types.Blob(data=audio_bytes, mime_type="audio/pcm;rate=16000")]
                        ),
                    )
                elif msg.type == InboundType.VIDEO and msg.data:
                    image_bytes = base64.b64decode(msg.data)
                    await session.send(
                        input=types.LiveClientRealtimeInput(
                            media_chunks=[types.Blob(data=image_bytes, mime_type="image/jpeg")]
                        ),
                    )
                elif msg.type == InboundType.TEXT and msg.text:
                    await session.send(input=msg.text, end_of_turn=True)
                    session_record.turn_count += 1
                elif msg.type == InboundType.END_TURN:
                    await session.send(input="", end_of_turn=True)

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
                    turn = session.receive()
                    async for response in turn:
                        # Model audio / text
                        if response.server_content is not None:
                            sc = response.server_content
                            if sc.model_turn and sc.model_turn.parts:
                                for part in sc.model_turn.parts:
                                    if part.inline_data and part.inline_data.data:
                                        audio_b64 = base64.b64encode(part.inline_data.data).decode("ascii")
                                        await _send_json(websocket, OutboundMessage(
                                            type=OutboundType.AUDIO, data=audio_b64,
                                        ))
                                    elif part.text:
                                        await _send_json(websocket, OutboundMessage(
                                            type=OutboundType.TRANSCRIPT, text=part.text,
                                        ))
                            # Transcribe user & model speech when available
                            if sc.input_transcription:
                                txt = getattr(sc.input_transcription, 'text', None)
                                if txt:
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.TRANSCRIPT, text=txt,
                                    ))
                            if sc.output_transcription:
                                txt = getattr(sc.output_transcription, 'text', None)
                                if txt:
                                    await _send_json(websocket, OutboundMessage(
                                        type=OutboundType.TRANSCRIPT, text=txt,
                                    ))
                            if sc.turn_complete:
                                await _send_json(websocket, OutboundMessage(type=OutboundType.TURN_COMPLETE))
                            if sc.interrupted:
                                await _send_json(websocket, OutboundMessage(type=OutboundType.INTERRUPTED))

                        # Tool / function calls
                        if response.tool_call is not None:
                            fn_responses: list[types.LiveClientToolResponse] = []
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
                                    types.LiveClientToolResponse(
                                        function_responses=[
                                            types.FunctionResponse(
                                                name=fc.name,
                                                response={"result": result_json},
                                            )
                                        ]
                                    )
                                )
                            for tr in fn_responses:
                                await session.send(input=tr)

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
