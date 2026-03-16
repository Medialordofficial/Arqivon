"""Agentic Tool Registry – callable tools exposed to the Gemini Live API via function calling.

Provides mode-specific tool sets for:
  • General assistant  – frame analysis, memory, UI actions
  • Translator         – live_translate, detect_language, translation_card
  • Tutor              – analyze_homework, provide_hint, grade_step, tutor_card
  • Support            – switch_topic, escalate_case, log_resolution, support_card
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any

from google.genai import types

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════════════════
# Individual Tool Implementations
# ═══════════════════════════════════════════════════════════════════════════════

# ── Shared / General ─────────────────────────────────────────────────────────

async def analyze_live_frame(
    *, frame_description: str = "", db: Any = None, user_id: str = "anonymous",
) -> str:
    logger.info("Tool: analyze_live_frame user=%s", user_id)
    return json.dumps({
        "status": "analyzed",
        "description": frame_description or "Frame received and analyzed.",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


async def upsert_firestore_memory(
    *, topic: str, details: str, db: Any = None, user_id: str = "anonymous",
) -> str:
    logger.info("Tool: upsert_firestore_memory topic=%s user=%s", topic, user_id)
    if db is not None:
        doc_ref = (
            db.collection("users").document(user_id)
            .collection("memories").document(topic)
        )
        await asyncio.to_thread(
            doc_ref.set,
            {"details": details, "updated_at": datetime.now(timezone.utc).isoformat(), "userId": user_id},
            merge=True,
        )
        return json.dumps({"status": "saved", "topic": topic})
    return json.dumps({"status": "skipped", "reason": "Firestore not initialized"})


async def create_ui_action(
    *, action_type: str, title: str = "", description: str = "",
    icon: str = "auto_awesome", primary_action_label: str = "OK",
    payload: dict[str, Any] | None = None,
    db: Any = None, user_id: str = "anonymous",
) -> str:
    logger.info("Tool: create_ui_action type=%s user=%s", action_type, user_id)
    return json.dumps({
        "status": "dispatched", "action_type": action_type,
        "title": title, "description": description,
    })


# ── Translator Mode ──────────────────────────────────────────────────────────

async def live_translate(
    *, source_text: str, translated_text: str = "", source_language: str = "auto",
    target_language: str = "en", formality: str = "neutral",
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Called when the model produces a translation for the user's speech."""
    logger.info("Tool: live_translate %s→%s user=%s", source_language, target_language, user_id)
    # The model itself does the translation; this tool is the structured output channel.
    return json.dumps({
        "status": "translated",
        "source_text": source_text,
        "source_language": source_language,
        "target_language": target_language,
        "translated_text": translated_text,
        "formality": formality,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


async def detect_language(
    *, text_sample: str, db: Any = None, user_id: str = "anonymous",
) -> str:
    """Detect the language of a text sample."""
    logger.info("Tool: detect_language user=%s", user_id)
    return json.dumps({
        "status": "detected",
        "sample": text_sample[:80],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


async def translation_card(
    *, original: str, translated: str, source_lang: str, target_lang: str,
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Create a saveable translation card shown to the user."""
    logger.info("Tool: translation_card user=%s", user_id)
    if db is not None:
        await asyncio.to_thread(
            db.collection("users").document(user_id).collection("translations").add,
            {"original": original, "translated": translated,
             "source_lang": source_lang, "target_lang": target_lang,
             "created_at": datetime.now(timezone.utc).isoformat()},
        )
    return json.dumps({"status": "card_created", "original": original, "translated": translated})


async def export_document(
    *, title: str, content: str, format: str = "pdf",
    sections: list[dict[str, str]] | None = None,
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Export translated content or any structured text as a document.

    The actual PDF generation happens client-side; this tool captures the
    structured content and sends it to the client for rendering.
    """
    logger.info("Tool: export_document title=%s format=%s user=%s", title, format, user_id)
    doc_data = {
        "title": title,
        "content": content,
        "format": format,
        "sections": sections or [],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    if db is not None:
        await asyncio.to_thread(
            db.collection("users").document(user_id).collection("exports").add,
            {**doc_data, "userId": user_id},
        )
    return json.dumps({"status": "export_ready", **doc_data})


# ── Tutor Mode ────────────────────────────────────────────────────────────────

async def analyze_homework(
    *, subject: str, description: str, difficulty: str = "medium",
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Analyse the homework/diagram shown via camera."""
    logger.info("Tool: analyze_homework subject=%s user=%s", subject, user_id)
    return json.dumps({
        "status": "analyzed", "subject": subject,
        "description": description, "difficulty": difficulty,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


async def solve_problem(
    *, subject: str, problem: str, solution_steps: list[str],
    final_answer: str, explanation: str = "",
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Solve a problem completely with step-by-step working and final answer.

    Called when the student requests a full solution rather than hints.
    """
    logger.info("Tool: solve_problem subject=%s user=%s", subject, user_id)
    result = {
        "status": "solved",
        "subject": subject,
        "problem": problem,
        "solution_steps": solution_steps,
        "final_answer": final_answer,
        "explanation": explanation,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    if db is not None:
        await asyncio.to_thread(
            db.collection("users").document(user_id).collection("solutions").add,
            {**result, "userId": user_id},
        )
    return json.dumps(result)


async def explain_concept(
    *, concept: str, subject: str, explanation: str,
    examples: list[str] | None = None, related_topics: list[str] | None = None,
    difficulty_level: str = "intermediate",
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Provide a rich explanation of an academic concept with examples."""
    logger.info("Tool: explain_concept concept=%s user=%s", concept, user_id)
    return json.dumps({
        "status": "explained",
        "concept": concept,
        "subject": subject,
        "explanation": explanation,
        "examples": examples or [],
        "related_topics": related_topics or [],
        "difficulty_level": difficulty_level,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    })


async def provide_hint(
    *, step_number: int, hint_text: str, concept: str = "",
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Push a contextual hint card without giving away the full answer."""
    logger.info("Tool: provide_hint step=%d user=%s", step_number, user_id)
    return json.dumps({
        "status": "hint_sent", "step_number": step_number,
        "hint_text": hint_text, "concept": concept,
    })


async def grade_step(
    *, step_number: int, is_correct: bool, feedback: str,
    correct_answer: str = "", next_step_hint: str = "",
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Grade one step of the student's work and provide targeted feedback."""
    logger.info("Tool: grade_step step=%d correct=%s user=%s", step_number, is_correct, user_id)
    return json.dumps({
        "status": "graded", "step_number": step_number,
        "is_correct": is_correct, "feedback": feedback,
        "correct_answer": correct_answer,
        "next_step_hint": next_step_hint,
    })


async def tutor_card(
    *, title: str, explanation: str, step_number: int = 0,
    total_steps: int = 0, progress_pct: float = 0.0,
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Render a rich tutor guidance card on the student's screen."""
    logger.info("Tool: tutor_card title=%s user=%s", title, user_id)
    return json.dumps({
        "status": "card_created", "title": title,
        "step_number": step_number, "total_steps": total_steps,
        "progress_pct": progress_pct,
    })


# ── Support Mode ──────────────────────────────────────────────────────────────

async def switch_topic(
    *, new_topic: str, reason: str = "",
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Track topic changes during a customer support conversation."""
    logger.info("Tool: switch_topic topic=%s user=%s", new_topic, user_id)
    if db is not None:
        await asyncio.to_thread(
            db.collection("users").document(user_id).collection("support_topics").add,
            {"topic": new_topic, "reason": reason,
             "timestamp": datetime.now(timezone.utc).isoformat()},
        )
    return json.dumps({"status": "topic_switched", "new_topic": new_topic})


async def escalate_case(
    *, severity: str, summary: str, category: str = "general",
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Escalate the case when the AI cannot resolve it."""
    logger.info("Tool: escalate_case severity=%s user=%s", severity, user_id)
    return json.dumps({
        "status": "escalated", "severity": severity, "category": category,
        "summary": summary,
    })


async def log_resolution(
    *, resolution: str, satisfaction: str = "unknown", follow_up: bool = False,
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Log how an issue was resolved."""
    logger.info("Tool: log_resolution user=%s", user_id)
    if db is not None:
        await asyncio.to_thread(
            db.collection("users").document(user_id).collection("resolutions").add,
            {"resolution": resolution, "satisfaction": satisfaction,
             "follow_up": follow_up, "timestamp": datetime.now(timezone.utc).isoformat()},
        )
    return json.dumps({"status": "logged", "resolution": resolution})


async def support_card(
    *, title: str, description: str, category: str = "general",
    options: list[str] | None = None,
    db: Any = None, user_id: str = "anonymous",
) -> str:
    """Render a support action card with contextual options."""
    logger.info("Tool: support_card title=%s user=%s", title, user_id)
    return json.dumps({
        "status": "card_created", "title": title,
        "category": category, "options": options or [],
    })


# ═══════════════════════════════════════════════════════════════════════════════
# Tool Declarations for Gemini Function Calling
# ═══════════════════════════════════════════════════════════════════════════════

_SHARED_DECLARATIONS: list[types.FunctionDeclaration] = [
    types.FunctionDeclaration(
        name="analyze_live_frame",
        description="Analyse the most recent camera frame visible to the user.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "frame_description": {
                    "type": "STRING",
                    "description": "A brief summary of what was detected in the frame.",
                },
            },
            "required": [],
        },
    ),
    types.FunctionDeclaration(
        name="upsert_firestore_memory",
        description="Permanently save a user preference or fact so it persists across sessions.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "topic": {"type": "STRING", "description": "Short topic key."},
                "details": {"type": "STRING", "description": "The information to persist."},
            },
            "required": ["topic", "details"],
        },
    ),
    types.FunctionDeclaration(
        name="create_ui_action",
        description="Render an interactive Smart Action Card on the user's screen.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "action_type": {
                    "type": "STRING",
                    "description": "One of: add_calendar, save_contact, translate, open_url, save_note, add_reminder, share.",
                },
                "title": {"type": "STRING", "description": "Card title."},
                "description": {"type": "STRING", "description": "Card body text."},
                "icon": {"type": "STRING", "description": "Material icon name."},
                "primary_action_label": {"type": "STRING", "description": "CTA label."},
            },
            "required": ["action_type", "title"],
        },
    ),
]

_TRANSLATOR_DECLARATIONS: list[types.FunctionDeclaration] = [
    types.FunctionDeclaration(
        name="live_translate",
        description=(
            "Produce a live translation of the user's spoken or typed text. "
            "ALWAYS call this with source and translated text so subtitles appear on screen. "
            "Also use this when translating documents, signs, menus, or any text shown via camera."
        ),
        parameters={
            "type": "OBJECT",
            "properties": {
                "source_text": {"type": "STRING", "description": "The original text in the source language."},
                "translated_text": {"type": "STRING", "description": "The translated text in the target language."},
                "source_language": {"type": "STRING", "description": "ISO 639-1 code of detected source language (e.g. 'es', 'fr')."},
                "target_language": {"type": "STRING", "description": "ISO 639-1 code of the target language."},
                "formality": {"type": "STRING", "description": "One of: formal, informal, neutral."},
            },
            "required": ["source_text", "translated_text", "target_language"],
        },
    ),
    types.FunctionDeclaration(
        name="detect_language",
        description="Detect the language of a text sample.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "text_sample": {"type": "STRING", "description": "Text to classify."},
            },
            "required": ["text_sample"],
        },
    ),
    types.FunctionDeclaration(
        name="translation_card",
        description="Create a saveable translation flashcard for important phrases or vocabulary.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "original": {"type": "STRING", "description": "Original phrase."},
                "translated": {"type": "STRING", "description": "Translated phrase."},
                "source_lang": {"type": "STRING", "description": "Source ISO code."},
                "target_lang": {"type": "STRING", "description": "Target ISO code."},
            },
            "required": ["original", "translated", "source_lang", "target_lang"],
        },
    ),
    types.FunctionDeclaration(
        name="export_document",
        description=(
            "Export translated content as a downloadable document (PDF). "
            "Use when the user asks to save, export, or download a translation."
        ),
        parameters={
            "type": "OBJECT",
            "properties": {
                "title": {"type": "STRING", "description": "Document title."},
                "content": {"type": "STRING", "description": "Full translated content as plain text or markdown."},
                "format": {"type": "STRING", "description": "Output format: pdf, text. Defaults to pdf."},
            },
            "required": ["title", "content"],
        },
    ),
]

_TUTOR_DECLARATIONS: list[types.FunctionDeclaration] = [
    types.FunctionDeclaration(
        name="analyze_homework",
        description="Analyse the homework, diagram, equation, or problem shown via the camera.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "subject": {"type": "STRING", "description": "Academic subject (math, physics, chemistry, biology, CS, history, geography…)."},
                "description": {"type": "STRING", "description": "What the problem/diagram contains."},
                "difficulty": {"type": "STRING", "description": "easy, medium, or hard."},
            },
            "required": ["subject", "description"],
        },
    ),
    types.FunctionDeclaration(
        name="solve_problem",
        description=(
            "Solve a problem completely with step-by-step working and a clear final answer. "
            "Use when the student asks to solve, answer, or complete a problem."
        ),
        parameters={
            "type": "OBJECT",
            "properties": {
                "subject": {"type": "STRING", "description": "Academic subject."},
                "problem": {"type": "STRING", "description": "The problem statement."},
                "solution_steps": {
                    "type": "ARRAY",
                    "items": {"type": "STRING"},
                    "description": "Ordered list of solution steps.",
                },
                "final_answer": {"type": "STRING", "description": "The final answer."},
                "explanation": {"type": "STRING", "description": "Additional explanation or reasoning."},
            },
            "required": ["subject", "problem", "solution_steps", "final_answer"],
        },
    ),
    types.FunctionDeclaration(
        name="explain_concept",
        description=(
            "Explain an academic concept with examples and related topics. "
            "Use when the student asks to understand or learn about a topic."
        ),
        parameters={
            "type": "OBJECT",
            "properties": {
                "concept": {"type": "STRING", "description": "The concept to explain."},
                "subject": {"type": "STRING", "description": "Academic subject."},
                "explanation": {"type": "STRING", "description": "Clear explanation of the concept."},
                "examples": {
                    "type": "ARRAY",
                    "items": {"type": "STRING"},
                    "description": "Illustrative examples.",
                },
                "related_topics": {
                    "type": "ARRAY",
                    "items": {"type": "STRING"},
                    "description": "Related topics to explore.",
                },
                "difficulty_level": {"type": "STRING", "description": "beginner, intermediate, or advanced."},
            },
            "required": ["concept", "subject", "explanation"],
        },
    ),
    types.FunctionDeclaration(
        name="provide_hint",
        description="Push a contextual hint without giving the full answer. Use when the student asks for hints.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "step_number": {"type": "INTEGER", "description": "Which step this hint belongs to."},
                "hint_text": {"type": "STRING", "description": "The hint content."},
                "concept": {"type": "STRING", "description": "The underlying concept being hinted at."},
            },
            "required": ["step_number", "hint_text"],
        },
    ),
    types.FunctionDeclaration(
        name="grade_step",
        description="Grade one step of the student's work with targeted feedback.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "step_number": {"type": "INTEGER", "description": "Step number being graded."},
                "is_correct": {"type": "BOOLEAN", "description": "Whether the step is correct."},
                "feedback": {"type": "STRING", "description": "Specific feedback on this step."},
                "correct_answer": {"type": "STRING", "description": "The correct answer if wrong."},
                "next_step_hint": {"type": "STRING", "description": "Hint for the next step."},
            },
            "required": ["step_number", "is_correct", "feedback"],
        },
    ),
    types.FunctionDeclaration(
        name="tutor_card",
        description="Render a rich step-by-step guidance card on the student's screen.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "title": {"type": "STRING", "description": "Card title."},
                "explanation": {"type": "STRING", "description": "Detailed explanation."},
                "step_number": {"type": "INTEGER", "description": "Current step."},
                "total_steps": {"type": "INTEGER", "description": "Total steps."},
                "progress_pct": {"type": "NUMBER", "description": "0.0–1.0 progress fraction."},
            },
            "required": ["title", "explanation"],
        },
    ),
    types.FunctionDeclaration(
        name="export_document",
        description=(
            "Export a solution, explanation, or study notes as a downloadable PDF. "
            "Use when the student asks to save, export, or download their work."
        ),
        parameters={
            "type": "OBJECT",
            "properties": {
                "title": {"type": "STRING", "description": "Document title."},
                "content": {"type": "STRING", "description": "Full content as plain text or markdown."},
                "format": {"type": "STRING", "description": "Output format: pdf, text. Defaults to pdf."},
            },
            "required": ["title", "content"],
        },
    ),
]

_SUPPORT_DECLARATIONS: list[types.FunctionDeclaration] = [
    types.FunctionDeclaration(
        name="switch_topic",
        description="Track when the customer changes topic mid-conversation.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "new_topic": {"type": "STRING", "description": "The new topic being discussed."},
                "reason": {"type": "STRING", "description": "Why the topic changed."},
            },
            "required": ["new_topic"],
        },
    ),
    types.FunctionDeclaration(
        name="escalate_case",
        description="Escalate the support case when the AI cannot resolve it.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "severity": {"type": "STRING", "description": "low, medium, high, critical."},
                "summary": {"type": "STRING", "description": "What was attempted and why escalation is needed."},
                "category": {"type": "STRING", "description": "Issue category."},
            },
            "required": ["severity", "summary"],
        },
    ),
    types.FunctionDeclaration(
        name="log_resolution",
        description="Log how an issue was resolved.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "resolution": {"type": "STRING", "description": "How the issue was resolved."},
                "satisfaction": {"type": "STRING", "description": "Customer satisfaction: happy, neutral, unhappy, unknown."},
                "follow_up": {"type": "BOOLEAN", "description": "Whether follow-up is needed."},
            },
            "required": ["resolution"],
        },
    ),
    types.FunctionDeclaration(
        name="support_card",
        description="Render a contextual support action card with selectable options.",
        parameters={
            "type": "OBJECT",
            "properties": {
                "title": {"type": "STRING", "description": "Card title."},
                "description": {"type": "STRING", "description": "Card body."},
                "category": {"type": "STRING", "description": "Issue category."},
            },
            "required": ["title", "description"],
        },
    ),
    types.FunctionDeclaration(
        name="export_document",
        description=(
            "Export a support resolution, troubleshooting guide, or summary as a downloadable document. "
            "Use when the user asks to save, export, or download support notes."
        ),
        parameters={
            "type": "OBJECT",
            "properties": {
                "title": {"type": "STRING", "description": "Document title."},
                "content": {"type": "STRING", "description": "Full content as plain text or markdown."},
                "format": {"type": "STRING", "description": "Output format: pdf, text. Defaults to pdf."},
            },
            "required": ["title", "content"],
        },
    ),
]


def get_tool_declarations(mode: str) -> list[types.FunctionDeclaration]:
    """Return the merged list of tool declarations for the given mode."""
    base = list(_SHARED_DECLARATIONS)
    extras = {
        "translator": _TRANSLATOR_DECLARATIONS,
        "tutor": _TUTOR_DECLARATIONS,
        "support": _SUPPORT_DECLARATIONS,
    }
    base.extend(extras.get(mode, []))
    return base


# Keep legacy flat list for backward compat
TOOL_DECLARATIONS = _SHARED_DECLARATIONS


# ═══════════════════════════════════════════════════════════════════════════════
# Dispatcher
# ═══════════════════════════════════════════════════════════════════════════════

TOOL_MAP: dict[str, Any] = {
    # Shared
    "analyze_live_frame": analyze_live_frame,
    "upsert_firestore_memory": upsert_firestore_memory,
    "create_ui_action": create_ui_action,
    # Translator
    "live_translate": live_translate,
    "detect_language": detect_language,
    "translation_card": translation_card,
    "export_document": export_document,
    # Tutor
    "analyze_homework": analyze_homework,
    "solve_problem": solve_problem,
    "explain_concept": explain_concept,
    "provide_hint": provide_hint,
    "grade_step": grade_step,
    "tutor_card": tutor_card,
    # Support
    "switch_topic": switch_topic,
    "escalate_case": escalate_case,
    "log_resolution": log_resolution,
    "support_card": support_card,
}


async def dispatch_tool_call(
    name: str,
    args: dict[str, Any],
    *,
    db: Any = None,
    user_id: str = "anonymous",
) -> str:
    """Look up *name* in the registry, execute with *args*, return JSON result."""
    fn = TOOL_MAP.get(name)
    if fn is None:
        return json.dumps({"error": f"Unknown tool: {name}"})
    try:
        return await fn(**args, db=db, user_id=user_id)
    except Exception as exc:
        logger.exception("Tool %s failed", name)
        return json.dumps({"error": str(exc)})
