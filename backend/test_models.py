"""Unit tests for backend Pydantic models."""

import pytest
from models import (
    AgentMode,
    InboundMessage, InboundType,
    OutboundMessage, OutboundType,
    SessionRecord,
)


class TestAgentMode:
    def test_all_modes_exist(self):
        assert len(AgentMode) == 4

    def test_mode_values(self):
        assert AgentMode.GENERAL.value == "general"
        assert AgentMode.TRANSLATOR.value == "translator"
        assert AgentMode.TUTOR.value == "tutor"
        assert AgentMode.SUPPORT.value == "support"

    def test_mode_from_string(self):
        assert AgentMode("general") == AgentMode.GENERAL
        assert AgentMode("translator") == AgentMode.TRANSLATOR

    def test_invalid_mode_raises(self):
        with pytest.raises(ValueError):
            AgentMode("invalid_mode")


class TestInboundMessage:
    def test_audio_message(self):
        msg = InboundMessage(type=InboundType.AUDIO, data="base64data")
        assert msg.type == InboundType.AUDIO
        assert msg.data == "base64data"
        assert msg.text is None

    def test_text_message(self):
        msg = InboundMessage(type=InboundType.TEXT, text="Hello world")
        assert msg.type == InboundType.TEXT
        assert msg.text == "Hello world"

    def test_set_mode_message(self):
        msg = InboundMessage(
            type=InboundType.SET_MODE,
            mode="translator",
            voice="Puck",
        )
        assert msg.mode == "translator"
        assert msg.voice == "Puck"

    def test_set_language_message(self):
        msg = InboundMessage(
            type=InboundType.SET_LANGUAGE,
            source_lang="fr",
            target_lang="de",
        )
        assert msg.source_lang == "fr"
        assert msg.target_lang == "de"

    def test_timestamp_auto_set(self):
        msg = InboundMessage(type=InboundType.PING)
        assert msg.timestamp > 0

    def test_json_serialization(self):
        msg = InboundMessage(type=InboundType.TEXT, text="Hi")
        json_str = msg.model_dump_json()
        assert "text" in json_str
        msg2 = InboundMessage.model_validate_json(json_str)
        assert msg2.text == "Hi"
        assert msg2.type == InboundType.TEXT


class TestOutboundMessage:
    def test_audio_message(self):
        msg = OutboundMessage(type=OutboundType.AUDIO, data="base64audio")
        assert msg.type == OutboundType.AUDIO
        assert msg.data == "base64audio"

    def test_error_message(self):
        msg = OutboundMessage(type=OutboundType.ERROR, text="Something failed")
        assert msg.type == OutboundType.ERROR
        assert msg.text == "Something failed"

    def test_ui_action_message(self):
        msg = OutboundMessage(
            type=OutboundType.UI_ACTION,
            action_type="open_url",
            payload={"title": "Visit", "description": "https://example.com"},
        )
        assert msg.action_type == "open_url"
        assert msg.payload["title"] == "Visit"

    def test_transcript_message(self):
        msg = OutboundMessage(type=OutboundType.TRANSCRIPT, text="Hello")
        assert msg.type == OutboundType.TRANSCRIPT
        assert msg.text == "Hello"

    def test_translation_message(self):
        msg = OutboundMessage(
            type=OutboundType.TRANSLATION,
            payload={
                "source_text": "Hola",
                "translated_text": "Hello",
                "source_language": "es",
                "target_language": "en",
            },
        )
        assert msg.payload["source_text"] == "Hola"

    def test_json_round_trip(self):
        msg = OutboundMessage(
            type=OutboundType.UI_ACTION,
            action_type="call",
            payload={"number": "+1-555-1234"},
        )
        json_str = msg.model_dump_json()
        msg2 = OutboundMessage.model_validate_json(json_str)
        assert msg2.action_type == "call"
        assert msg2.payload["number"] == "+1-555-1234"

    def test_all_outbound_types_exist(self):
        expected = {
            "audio", "text", "ui_action", "transcript", "user_transcript",
            "translation", "tutor_step", "support_topic", "export",
            "status", "error", "pong", "session_saved", "turn_complete",
            "interrupted", "mode_changed",
        }
        actual = {t.value for t in OutboundType}
        assert expected == actual


class TestSessionRecord:
    def test_default_values(self):
        rec = SessionRecord(session_id="s1", user_id="u1")
        assert rec.session_id == "s1"
        assert rec.user_id == "u1"
        assert rec.title == "Untitled Session"
        assert rec.summary == ""
        assert rec.mode == "general"
        assert rec.source_lang == "auto"
        assert rec.target_lang == "en"
        assert rec.started_at > 0
        assert rec.ended_at is None
        assert rec.turn_count == 0
        assert rec.tags == []
        assert rec.topics == []

    def test_custom_values(self):
        rec = SessionRecord(
            session_id="s2",
            user_id="u2",
            title="Translation Session",
            mode="translator",
            source_lang="fr",
            target_lang="en",
            turn_count=15,
            tags=["language"],
            topics=["greetings"],
        )
        assert rec.title == "Translation Session"
        assert rec.mode == "translator"
        assert rec.turn_count == 15
        assert "language" in rec.tags
        assert "greetings" in rec.topics

    def test_model_dump(self):
        rec = SessionRecord(session_id="s3", user_id="u3")
        data = rec.model_dump()
        assert isinstance(data, dict)
        assert data["session_id"] == "s3"
        assert "started_at" in data

    def test_mutable_turn_count(self):
        rec = SessionRecord(session_id="s4", user_id="u4")
        rec.turn_count += 1
        rec.turn_count += 1
        assert rec.turn_count == 2

    def test_mutable_topics(self):
        rec = SessionRecord(session_id="s5", user_id="u5")
        rec.topics.append("Billing")
        rec.topics.append("Returns")
        assert len(rec.topics) == 2

    def test_ended_at_can_be_set(self):
        rec = SessionRecord(session_id="s6", user_id="u6")
        rec.ended_at = 1700000000.0
        assert rec.ended_at == 1700000000.0
