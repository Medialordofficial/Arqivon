#!/usr/bin/env python3
"""
Arqivon Live Pipeline Tester
==============================
Connects to the deployed backend WebSocket and monitors the complete
audio pipeline in real-time.  Reports:

  • Audio chunk count, sizes, and inter-arrival timing
  • Transcript chunk count and text
  • turn_complete / interrupted timing
  • Audio-transcript alignment (total audio bytes vs transcript length)
  • Latency from first audio to turn_complete
  • Any errors or unexpected messages

Usage:
  # Against deployed backend (requires Firebase auth token):
  python live_tester.py --url wss://arqivon-backend-XXXX.run.app/ws/test_user --token FIREBASE_TOKEN

  # Against local backend:
  python live_tester.py --url ws://localhost:8000/ws/test_user --token FIREBASE_TOKEN

  # Monitor-only mode (connects and watches, doesn't send audio):
  python live_tester.py --url ws://... --token ... --monitor-only

  # Send a text query to trigger a response:
  python live_tester.py --url ws://... --token ... --text "Tell me a long story about a dragon"
"""

import argparse
import asyncio
import base64
import json
import struct
import sys
import time
from dataclasses import dataclass, field

try:
    import websockets
except ImportError:
    print("ERROR: websockets package required. Install: pip install websockets")
    sys.exit(1)


@dataclass
class TurnStats:
    """Statistics for a single AI turn."""
    start_time: float = 0.0
    first_audio_time: float = 0.0
    last_audio_time: float = 0.0
    complete_time: float = 0.0
    audio_chunk_count: int = 0
    audio_total_bytes: int = 0
    audio_chunk_sizes: list = field(default_factory=list)
    audio_inter_arrival_ms: list = field(default_factory=list)
    transcript_chunks: list = field(default_factory=list)
    transcript_full: str = ""
    user_transcript_full: str = ""
    was_interrupted: bool = False


class LiveTester:
    def __init__(self, url: str, token: str, mode: str = "general",
                 voice: str = "Aoede", monitor_only: bool = False,
                 text_query: str | None = None):
        self.url = url
        self.token = token
        self.mode = mode
        self.voice = voice
        self.monitor_only = monitor_only
        self.text_query = text_query

        self.ws = None
        self.connected = False
        self.turns: list[TurnStats] = []
        self.current_turn: TurnStats | None = None
        self.total_messages = 0
        self.errors: list[str] = []
        self._running = True

    async def connect(self):
        """Connect to the backend WebSocket."""
        full_url = f"{self.url}?token={self.token}"
        print(f"\n{'='*60}")
        print(f"  ARQIVON LIVE PIPELINE TESTER")
        print(f"{'='*60}")
        print(f"  URL:    {self.url}")
        print(f"  Mode:   {self.mode}")
        print(f"  Voice:  {self.voice}")
        print(f"  Monitor: {self.monitor_only}")
        if self.text_query:
            print(f"  Query:  {self.text_query[:50]}...")
        print(f"{'='*60}\n")

        try:
            self.ws = await websockets.connect(
                full_url,
                ping_interval=20,
                ping_timeout=60,
                max_size=10 * 1024 * 1024,  # 10 MB
            )
            self.connected = True
            print("✓ WebSocket connected\n")
        except Exception as e:
            print(f"✗ Connection failed: {e}")
            return False
        return True

    async def run(self):
        """Main test flow."""
        if not await self.connect():
            return

        # Start receiver task
        receiver = asyncio.create_task(self._receive_loop())

        try:
            # Wait for initial status
            await asyncio.sleep(1.0)

            # Send set_mode to initialize Gemini session
            await self._send({
                "type": "set_mode",
                "mode": self.mode,
                "voice": self.voice,
            })
            print(f"→ Sent set_mode: {self.mode} / {self.voice}")
            await asyncio.sleep(2.0)

            if self.text_query:
                # Send text query to trigger AI response
                self.current_turn = TurnStats(start_time=time.monotonic())
                await self._send({
                    "type": "text",
                    "text": self.text_query,
                })
                print(f"\n→ Sent text query: \"{self.text_query}\"")
                print(f"  Waiting for AI response...\n")

                # Wait for response (up to 60 seconds)
                for _ in range(600):
                    await asyncio.sleep(0.1)
                    if self.current_turn and self.current_turn.complete_time > 0:
                        break
                    if not self._running:
                        break

                # Wait a bit more for any trailing messages
                await asyncio.sleep(1.0)

            elif not self.monitor_only:
                # Generate and send test audio (1 second of silence)
                print("→ Sending 1s of silent PCM audio...")
                self.current_turn = TurnStats(start_time=time.monotonic())
                await self._send_test_audio(duration_s=1.0)
                print("→ Audio sent. Waiting for response...\n")

                # Wait for response
                for _ in range(300):
                    await asyncio.sleep(0.1)
                    if self.current_turn and self.current_turn.complete_time > 0:
                        break
                    if not self._running:
                        break
                await asyncio.sleep(1.0)

            else:
                # Monitor mode — just listen
                print("→ Monitor mode: listening for messages...")
                print("  (Press Ctrl+C to stop)\n")
                try:
                    await asyncio.wait_for(receiver, timeout=None)
                except asyncio.CancelledError:
                    pass

        except KeyboardInterrupt:
            print("\n\n[Interrupted by user]")
        finally:
            self._running = False
            receiver.cancel()
            try:
                await receiver
            except asyncio.CancelledError:
                pass
            if self.ws:
                await self.ws.close()

        # Print report
        self._print_report()

    async def _receive_loop(self):
        """Receive and analyze all messages from the backend."""
        try:
            async for raw in self.ws:
                self.total_messages += 1
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    self.errors.append(f"Invalid JSON: {raw[:100]}")
                    continue

                msg_type = msg.get("type", "unknown")
                now = time.monotonic()

                if msg_type == "audio":
                    self._handle_audio(msg, now)
                elif msg_type == "transcript":
                    self._handle_transcript(msg, now)
                elif msg_type == "user_transcript":
                    self._handle_user_transcript(msg, now)
                elif msg_type == "turn_complete":
                    self._handle_turn_complete(now)
                elif msg_type == "interrupted":
                    self._handle_interrupted(now)
                elif msg_type == "mode_changed":
                    print(f"  ◆ mode_changed: {msg.get('text', '?')}")
                elif msg_type == "error":
                    err = msg.get("text", "Unknown error")
                    self.errors.append(err)
                    print(f"  ✗ ERROR: {err}")
                elif msg_type == "pong":
                    pass  # heartbeat, ignore
                elif msg_type == "status":
                    print(f"  ◆ status: {msg.get('text', '?')}")
                elif msg_type == "session_saved":
                    print(f"  ◆ session_saved: {msg.get('payload', {}).get('title', '?')}")
                else:
                    print(f"  ◆ {msg_type}: {json.dumps(msg)[:100]}")

        except websockets.ConnectionClosed as e:
            print(f"\n  ✗ WebSocket closed: {e}")
        except Exception as e:
            print(f"\n  ✗ Receive error: {e}")

    def _handle_audio(self, msg: dict, now: float):
        """Process an incoming audio chunk."""
        if not self.current_turn:
            self.current_turn = TurnStats(start_time=now)

        t = self.current_turn
        data = msg.get("data", "")
        raw_bytes = base64.b64decode(data) if data else b""
        chunk_size = len(raw_bytes)
        duration_ms = (chunk_size / (24000 * 2)) * 1000  # 24kHz 16-bit mono

        t.audio_chunk_count += 1
        t.audio_total_bytes += chunk_size
        t.audio_chunk_sizes.append(chunk_size)

        if t.first_audio_time == 0:
            t.first_audio_time = now
            latency_ms = (now - t.start_time) * 1000
            print(f"  ♪ First audio chunk: {chunk_size} bytes "
                  f"({duration_ms:.0f}ms audio) "
                  f"[latency: {latency_ms:.0f}ms]")
        else:
            inter_ms = (now - t.last_audio_time) * 1000
            t.audio_inter_arrival_ms.append(inter_ms)

        t.last_audio_time = now

        # Log every 10th chunk
        if t.audio_chunk_count % 10 == 0:
            total_audio_ms = (t.audio_total_bytes / (24000 * 2)) * 1000
            print(f"  ♪ Audio chunk #{t.audio_chunk_count}: "
                  f"{chunk_size} bytes ({duration_ms:.0f}ms), "
                  f"total={t.audio_total_bytes} bytes "
                  f"({total_audio_ms:.0f}ms audio)")

    def _handle_transcript(self, msg: dict, now: float):
        """Process an AI transcript chunk."""
        if not self.current_turn:
            self.current_turn = TurnStats(start_time=now)

        text = msg.get("text", "")
        self.current_turn.transcript_chunks.append(text)
        self.current_turn.transcript_full += text + " "
        print(f"  📝 Transcript: \"{text}\"")

    def _handle_user_transcript(self, msg: dict, now: float):
        """Process a user transcript chunk."""
        if self.current_turn:
            text = msg.get("text", "")
            self.current_turn.user_transcript_full += text + " "
            print(f"  🎤 User: \"{text}\"")

    def _handle_turn_complete(self, now: float):
        """Process turn_complete signal."""
        if self.current_turn:
            t = self.current_turn
            t.complete_time = now
            duration_ms = (now - t.start_time) * 1000
            audio_ms = (t.audio_total_bytes / (24000 * 2)) * 1000

            print(f"\n  ✓ TURN COMPLETE")
            print(f"    Duration:     {duration_ms:.0f}ms")
            print(f"    Audio chunks: {t.audio_chunk_count}")
            print(f"    Audio bytes:  {t.audio_total_bytes}")
            print(f"    Audio time:   {audio_ms:.0f}ms")
            print(f"    Transcript:   {len(t.transcript_chunks)} chunks")
            if t.first_audio_time > 0:
                first_token_ms = (t.first_audio_time - t.start_time) * 1000
                print(f"    First token:  {first_token_ms:.0f}ms")
            print()

            self.turns.append(t)
            self.current_turn = None
        else:
            print(f"  ✓ turn_complete (no turn in progress)")

    def _handle_interrupted(self, now: float):
        """Process interrupted signal."""
        if self.current_turn:
            t = self.current_turn
            t.complete_time = now
            t.was_interrupted = True
            duration_ms = (now - t.start_time) * 1000
            print(f"\n  ⚡ INTERRUPTED after {duration_ms:.0f}ms "
                  f"({t.audio_chunk_count} audio chunks)")
            self.turns.append(t)
            self.current_turn = None
        else:
            print(f"  ⚡ interrupted (no turn in progress)")

    async def _send(self, msg: dict):
        """Send a JSON message to the backend."""
        msg["timestamp"] = time.time()
        await self.ws.send(json.dumps(msg))

    async def _send_test_audio(self, duration_s: float = 1.0):
        """Send silent PCM audio to trigger VAD and get a response."""
        sample_rate = 16000
        total_samples = int(sample_rate * duration_s)
        chunk_samples = 800  # 50ms chunks at 16kHz
        chunk_bytes = chunk_samples * 2  # 16-bit

        for i in range(0, total_samples, chunk_samples):
            # Generate silent audio (zeros)
            pcm = b'\x00' * chunk_bytes
            b64 = base64.b64encode(pcm).decode('ascii')
            await self._send({"type": "audio", "data": b64})
            await asyncio.sleep(0.05)  # 50ms between chunks

    def _print_report(self):
        """Print final test report."""
        print(f"\n{'='*60}")
        print(f"  PIPELINE TEST REPORT")
        print(f"{'='*60}")
        print(f"  Total messages received: {self.total_messages}")
        print(f"  Total turns:             {len(self.turns)}")
        print(f"  Errors:                  {len(self.errors)}")

        if self.errors:
            print(f"\n  ERRORS:")
            for err in self.errors:
                print(f"    ✗ {err}")

        for i, t in enumerate(self.turns):
            print(f"\n  {'─'*50}")
            print(f"  Turn #{i+1} {'(INTERRUPTED)' if t.was_interrupted else ''}")
            print(f"  {'─'*50}")

            duration_ms = (t.complete_time - t.start_time) * 1000
            audio_ms = (t.audio_total_bytes / (24000 * 2)) * 1000 if t.audio_total_bytes > 0 else 0
            word_count = len(t.transcript_full.split()) if t.transcript_full.strip() else 0

            print(f"    Wall time:        {duration_ms:.0f}ms")
            print(f"    Audio chunks:     {t.audio_chunk_count}")
            print(f"    Audio bytes:      {t.audio_total_bytes:,}")
            print(f"    Audio duration:   {audio_ms:.0f}ms ({audio_ms/1000:.1f}s)")
            print(f"    Transcript words: {word_count}")
            print(f"    Transcript:       \"{t.transcript_full.strip()[:200]}\"")

            if t.first_audio_time > 0 and t.start_time > 0:
                first_token_ms = (t.first_audio_time - t.start_time) * 1000
                print(f"    First audio lag:  {first_token_ms:.0f}ms")

            if t.audio_chunk_sizes:
                sizes = t.audio_chunk_sizes
                avg_size = sum(sizes) / len(sizes)
                min_size = min(sizes)
                max_size = max(sizes)
                print(f"    Chunk sizes:      min={min_size}, avg={avg_size:.0f}, max={max_size}")

            if t.audio_inter_arrival_ms:
                iats = t.audio_inter_arrival_ms
                avg_iat = sum(iats) / len(iats)
                min_iat = min(iats)
                max_iat = max(iats)
                sorted_iats = sorted(iats)
                p95 = sorted_iats[int(len(sorted_iats) * 0.95)] if len(sorted_iats) >= 2 else sorted_iats[-1]
                print(f"    Inter-arrival:    min={min_iat:.0f}ms, avg={avg_iat:.0f}ms, "
                      f"p95={p95:.0f}ms, max={max_iat:.0f}ms")

            # Audio-transcript alignment check
            if audio_ms > 0 and word_count > 0:
                # Rough estimate: average speech is ~2.5 words/second
                expected_audio_ms = word_count / 2.5 * 1000
                ratio = audio_ms / expected_audio_ms if expected_audio_ms > 0 else 0
                alignment = "GOOD" if 0.5 < ratio < 2.0 else "MISALIGNED"
                print(f"    Audio/text ratio: {ratio:.2f} ({alignment})")
                if alignment == "MISALIGNED":
                    print(f"      ⚠ Expected ~{expected_audio_ms:.0f}ms audio for "
                          f"{word_count} words, got {audio_ms:.0f}ms")

        if not self.turns:
            print(f"\n  ⚠ No turns completed — check connection and auth token")

        print(f"\n{'='*60}")
        print(f"  END OF REPORT")
        print(f"{'='*60}\n")


async def main():
    parser = argparse.ArgumentParser(
        description="Arqivon Live Pipeline Tester",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--url", required=True,
                        help="WebSocket URL (e.g., wss://host/ws/user_id)")
    parser.add_argument("--token", required=True,
                        help="Firebase auth token")
    parser.add_argument("--mode", default="general",
                        choices=["general", "translator", "tutor", "support"],
                        help="Agent mode (default: general)")
    parser.add_argument("--voice", default="Aoede",
                        help="Voice name (default: Aoede)")
    parser.add_argument("--monitor-only", action="store_true",
                        help="Only monitor, don't send audio or text")
    parser.add_argument("--text", type=str, default=None,
                        help="Text query to send (triggers AI response)")

    args = parser.parse_args()

    tester = LiveTester(
        url=args.url,
        token=args.token,
        mode=args.mode,
        voice=args.voice,
        monitor_only=args.monitor_only,
        text_query=args.text,
    )
    await tester.run()


if __name__ == "__main__":
    asyncio.run(main())
