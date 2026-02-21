"""Pydantic models for typed WebSocket message transport."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


# ── Agent Modes ───────────────────────────────────────────────────────────────

class AgentMode(str, Enum):
    """The operating mode determines the system prompt & active tool-set."""
    GENERAL = "general"
    TRANSLATOR = "translator"
    TUTOR = "tutor"
    SUPPORT = "support"


# ── Inbound (Client → Server) ────────────────────────────────────────────────

class InboundType(str, Enum):
    AUDIO = "audio"
    VIDEO = "video"
    TEXT = "text"
    PING = "ping"
    END_TURN = "end_turn"
    SET_MODE = "set_mode"           # client selects agent mode
    SET_LANGUAGE = "set_language"   # for translator mode


class InboundMessage(BaseModel):
    type: InboundType
    data: str | None = None          # base64-encoded binary or plain text
    text: str | None = None          # used only for type=text
    mode: str | None = None          # for SET_MODE messages
    source_lang: str | None = None   # for SET_LANGUAGE (translator)
    target_lang: str | None = None   # for SET_LANGUAGE (translator)
    timestamp: float = Field(default_factory=lambda: datetime.utcnow().timestamp())


# ── Outbound (Server → Client) ───────────────────────────────────────────────

class OutboundType(str, Enum):
    AUDIO = "audio"
    TEXT = "text"
    UI_ACTION = "ui_action"
    TRANSCRIPT = "transcript"
    TRANSLATION = "translation"     # live translation text overlay
    TUTOR_STEP = "tutor_step"       # step-by-step tutor guidance
    SUPPORT_TOPIC = "support_topic" # topic tracking for customer support
    STATUS = "status"
    ERROR = "error"
    PONG = "pong"
    SESSION_SAVED = "session_saved"
    TURN_COMPLETE = "turn_complete"
    INTERRUPTED = "interrupted"
    MODE_CHANGED = "mode_changed"


class OutboundMessage(BaseModel):
    type: OutboundType
    data: str | None = None
    text: str | None = None
    action_type: str | None = None
    payload: dict[str, Any] | None = None
    timestamp: float = Field(default_factory=lambda: datetime.utcnow().timestamp())


# ── Session persistence ──────────────────────────────────────────────────────

class SessionRecord(BaseModel):
    session_id: str
    user_id: str
    title: str = "Untitled Session"
    summary: str = ""
    mode: str = AgentMode.GENERAL.value
    source_lang: str = "auto"
    target_lang: str = "en"
    started_at: float = Field(default_factory=lambda: datetime.utcnow().timestamp())
    ended_at: float | None = None
    turn_count: int = 0
    tags: list[str] = Field(default_factory=list)
    topics: list[str] = Field(default_factory=list)    # support-agent topic trail
    thumbnail_url: str | None = None
