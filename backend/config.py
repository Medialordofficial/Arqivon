"""Application configuration loaded from environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

# Load .env from the same directory as this file (works whether run from the
# project root or the backend/ dir).
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))


@dataclass(frozen=True, slots=True)
class Settings:
    """Immutable application settings."""

    gemini_api_key: str = field(default_factory=lambda: os.environ.get("GEMINI_API_KEY", ""))
    gemini_model: str = field(default_factory=lambda: os.environ.get("GEMINI_MODEL", "gemini-2.5-flash-native-audio-latest"))
    gcp_project_id: str = field(default_factory=lambda: os.environ.get("GCP_PROJECT_ID", ""))
    gcs_bucket: str = field(default_factory=lambda: os.environ.get("GCS_BUCKET", "arqivon-inc.firebasestorage.app"))
    briefing_api_key: str = field(default_factory=lambda: os.environ.get("BRIEFING_API_KEY", ""))

    # Server
    host: str = "0.0.0.0"
    port: int = int(os.environ.get("PORT", "8080"))

    # WebSocket
    ws_heartbeat_interval: float = 15.0
    ws_max_reconnect_attempts: int = 5

    # Audio
    audio_sample_rate: int = 16000
    audio_channels: int = 1

    # Video
    video_fps: int = 2
    video_quality: int = 60  # JPEG quality


settings = Settings()
