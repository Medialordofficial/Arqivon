import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_mode.dart';
import '../models/chat_message.dart';
import '../models/reminder_model.dart';
import '../models/smart_action.dart';
import '../models/ws_message.dart';
import '../config/logger.dart';
import '../providers/notes_provider.dart';
import '../providers/session_provider.dart';
import '../services/audio_service.dart';
import '../services/websocket_service.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

/// Session ID to resume when the next session starts.
final resumeSessionProvider = StateProvider<String?>((ref) => null);

/// Controls the active tab index in MainNavigator.
final activeTabProvider = StateProvider<int>((ref) => 0);

/// Exposed live session state.
class LiveSessionState {
  final WsConnectionState connectionState;
  final bool isStreaming;

  /// True while Gemini is streaming audio back to the user.
  final bool isResponding;

  /// True when the mic is muted (not sending audio). Default is muted.
  final bool isMuted;
  final AgentMode mode;
  final String? transcript;
  final String? userTranscript;
  final SmartAction? currentAction;
  final List<SmartAction> actionHistory;

  // Translator
  final TranslationOverlay? currentTranslation;
  final List<TranslationOverlay> translationHistory;
  final String sourceLang;
  final String targetLang;

  // Tutor
  final TutorStep? currentTutorStep;
  final List<TutorStep> tutorSteps;

  // Support
  final SupportTopic? currentSupportTopic;
  final List<SupportTopic> supportTopics;

  // Export
  final ExportDocument? pendingExport;

  // Chat transcript
  final List<ChatMessage> chatMessages;

  // Photo capture
  final String? pendingPhotoCapture;

  // Post-session insights card
  final SessionInsights? sessionInsights;

  const LiveSessionState({
    this.connectionState = WsConnectionState.disconnected,
    this.isStreaming = false,
    this.isResponding = false,
    this.isMuted = true,
    this.mode = AgentMode.general, // overridden in build() with user default
    this.transcript,
    this.userTranscript,
    this.currentAction,
    this.actionHistory = const [],
    this.currentTranslation,
    this.translationHistory = const [],
    this.sourceLang = 'auto',
    this.targetLang = 'en',
    this.currentTutorStep,
    this.tutorSteps = const [],
    this.currentSupportTopic,
    this.supportTopics = const [],
    this.pendingExport,
    this.chatMessages = const [],
    this.pendingPhotoCapture,
    this.sessionInsights,
  });

  LiveSessionState copyWith({
    WsConnectionState? connectionState,
    bool? isStreaming,
    bool? isResponding,
    bool? isMuted,
    AgentMode? mode,
    String? transcript,
    bool clearTranscript = false,
    String? userTranscript,
    bool clearUserTranscript = false,
    SmartAction? currentAction,
    bool clearAction = false,
    List<SmartAction>? actionHistory,
    TranslationOverlay? currentTranslation,
    bool clearTranslation = false,
    List<TranslationOverlay>? translationHistory,
    String? sourceLang,
    String? targetLang,
    TutorStep? currentTutorStep,
    bool clearTutorStep = false,
    List<TutorStep>? tutorSteps,
    SupportTopic? currentSupportTopic,
    bool clearSupportTopic = false,
    List<SupportTopic>? supportTopics,
    ExportDocument? pendingExport,
    bool clearExport = false,
    List<ChatMessage>? chatMessages,
    String? pendingPhotoCapture,
    bool clearPhotoCapture = false,
    SessionInsights? sessionInsights,
    bool clearSessionInsights = false,
  }) {
    return LiveSessionState(
      connectionState: connectionState ?? this.connectionState,
      isStreaming: isStreaming ?? this.isStreaming,
      isResponding: isResponding ?? this.isResponding,
      isMuted: isMuted ?? this.isMuted,
      mode: mode ?? this.mode,
      transcript: clearTranscript ? null : (transcript ?? this.transcript),
      userTranscript:
          clearUserTranscript ? null : (userTranscript ?? this.userTranscript),
      currentAction: clearAction ? null : (currentAction ?? this.currentAction),
      actionHistory: actionHistory ?? this.actionHistory,
      currentTranslation: clearTranslation
          ? null
          : (currentTranslation ?? this.currentTranslation),
      translationHistory: translationHistory ?? this.translationHistory,
      sourceLang: sourceLang ?? this.sourceLang,
      targetLang: targetLang ?? this.targetLang,
      currentTutorStep:
          clearTutorStep ? null : (currentTutorStep ?? this.currentTutorStep),
      tutorSteps: tutorSteps ?? this.tutorSteps,
      currentSupportTopic: clearSupportTopic
          ? null
          : (currentSupportTopic ?? this.currentSupportTopic),
      supportTopics: supportTopics ?? this.supportTopics,
      pendingExport: clearExport ? null : (pendingExport ?? this.pendingExport),
      chatMessages: chatMessages ?? this.chatMessages,
      pendingPhotoCapture: clearPhotoCapture
          ? null
          : (pendingPhotoCapture ?? this.pendingPhotoCapture),
      sessionInsights: clearSessionInsights
          ? null
          : (sessionInsights ?? this.sessionInsights),
    );
  }
}

/// Post-session insights displayed after the user stops a session.
class SessionInsights {
  final String sessionId;
  final String title;
  final String summary;
  final int turnCount;
  final int notesSaved;
  final List<String> topics;
  final AgentMode mode;
  final Duration duration;

  const SessionInsights({
    required this.sessionId,
    this.title = 'Session Complete',
    this.summary = '',
    this.turnCount = 0,
    this.notesSaved = 0,
    this.topics = const [],
    this.mode = AgentMode.general,
    this.duration = Duration.zero,
  });
}

/// The core Live session provider managing WebSocket + audio pipeline.
class LiveSessionNotifier extends AutoDisposeAsyncNotifier<LiveSessionState> {
  static final _log = AppLogger('LiveSession');

  WebSocketService? _ws;
  AudioCaptureService? _audio;
  StreamSubscription? _msgSub;
  StreamSubscription? _stateSub;
  int _audioChunksSent = 0;

  StreamSubscription? _audioSub;
  StreamSubscription? _ampSub;

  /// Debounce timer for mode switches — prevents rapid-fire set_mode
  /// messages to the backend when the user taps modes quickly.
  Timer? _modeSwitchDebounce;

  /// Set true during intentional disconnect (stopSession) to prevent
  /// auto-recovery from firing.
  bool _intentionalDisconnect = false;

  // ── Watchdog timers ────────────────────────────────────────────────
  /// Detects when the Android recorder silently dies (no onDone, no data).
  Timer? _recorderWatchdog;
  int _lastWatchdogChunkCount = 0;
  int _watchdogStallCount = 0;

  /// Detects when the backend/Gemini stops responding entirely.
  Timer? _responseWatchdog;

  /// Detects when no new audio chunks arrive during AI response.
  Timer? _responseStaleTimer;
  bool _restartInFlight = false;
  bool _wsWasReconnecting = false;
  Timer? _turnCompleteTimer;

  /// Timestamp of the last `interrupted` event. Audio chunks arriving within
  /// 300 ms of this timestamp are trailing chunks from the interrupted
  /// response and must be silently dropped.
  DateTime? _interruptedAt;

  /// Accumulated user/AI text within the current Gemini turn.
  /// Saved as ChatMessages on turn_complete.
  final List<String> _turnUserTexts = [];
  final List<String> _turnAiTexts = [];

  /// AI text deferred until playback finishes so it doesn't spoil the audio.
  String _pendingAiText = '';

  /// Count of notes saved during the current session for insights.
  int _notesSavedThisSession = 0;

  /// Tracks when the server last confirmed user speech (user_transcript).
  /// Used by the response watchdog to detect "user spoke but no AI response."
  DateTime? _lastUserTranscriptAt;

  /// Amplitude notifier for the orb visualizer — avoids high-frequency

  // ── Client-side latency tracking ─────────────────────────────────
  /// Rolling average of server→client one-way latency in milliseconds.
  /// Updated from the `timestamp` field of outbound messages.
  double _avgServerHopMs = 0;
  int _hopSamples = 0;
  static const int _maxHopSamples = 50;

  void _trackLatency(WsOutbound msg) {
    if (msg.timestamp == null || msg.timestamp! <= 0) return;
    final serverTs = msg.timestamp!;
    final clientTs = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final hopMs = (clientTs - serverTs) * 1000;
    if (hopMs < 0 || hopMs > 10000) return; // clock skew — ignore
    _hopSamples++;
    // Exponential moving average (alpha stabilises after _maxHopSamples).
    final effectiveSamples = _hopSamples.clamp(1, _maxHopSamples);
    final alpha = 2.0 / (effectiveSamples + 1);
    _avgServerHopMs = alpha * hopMs + (1 - alpha) * _avgServerHopMs;
    if (_hopSamples <= 100 && _hopSamples % 20 == 0) {
      _log.info(
          'Server→client latency: ${_avgServerHopMs.toStringAsFixed(0)}ms (avg)');
    }
  }

  /// Riverpod state rebuilds by using a ValueNotifier instead.
  final ValueNotifier<double> amplitudeNotifier = ValueNotifier<double>(0.0);

  // Track which mode was last sent to the backend so we avoid triggering an
  // unnecessary Gemini session restart on every mic tap.
  AgentMode? _lastSentMode;

  /// Shared WS state listener used by both connectOnly() and startSession().
  void _onWsStateChange(WsConnectionState s) {
    final cur = state.valueOrNull ?? const LiveSessionState();
    state = AsyncData(cur.copyWith(connectionState: s));
    if (s == WsConnectionState.reconnecting) {
      _wsWasReconnecting = true;
    }
    if (s == WsConnectionState.connected && _wsWasReconnecting) {
      _wsWasReconnecting = false;
      if (cur.isStreaming) {
        _log.info('WS auto-reconnected — re-sending set_mode');
        final selectedVoice = ref.read(settingsProvider).selectedVoice;
        _ws?.send(WsInbound(
          type: 'set_mode',
          mode: cur.mode.wsValue,
          voice: selectedVoice,
        ));
        _lastSentMode = cur.mode;
      }
    }
    // Auto-recover: if the WS exhausted all retries and transitioned to
    // disconnected while the user hasn't intentionally stopped, create
    // a fresh WS and start a new reconnect cycle.  This prevents the UI
    // from being permanently stuck after e.g. a backend cold start
    // that outlasted the first batch of retries.
    if (s == WsConnectionState.disconnected && !_intentionalDisconnect) {
      _log.warning(
        'WS went disconnected (streaming=${cur.isStreaming}) — '
        'scheduling full reconnect in 5s',
      );
      Future.delayed(const Duration(seconds: 5), () {
        final latest = state.valueOrNull;
        if (latest != null &&
            latest.connectionState == WsConnectionState.disconnected &&
            !_intentionalDisconnect) {
          _log.info('Auto-recovering WS connection');
          connectOnly();
        }
      });
    }
  }

  @override
  Future<LiveSessionState> build() async {
    ref.onDispose(_cleanup);
    final settings = ref.read(settingsProvider);
    return LiveSessionState(mode: settings.defaultMode);
  }

  // ── Mode Management ───────────────────────────────────────────────────

  void setMode(AgentMode newMode) {
    final current = state.valueOrNull ?? const LiveSessionState();
    // Cancel any pending turn_complete finalization from the old mode.
    _turnCompleteTimer?.cancel();
    // Stop any in-flight playback from the old mode so stale audio doesn't
    // bleed across modes during the video demo.
    if (current.isResponding) {
      _audio?.stopPlayback();
      // Set the interrupt guard so trailing audio chunks from the old
      // mode that are still in the WebSocket pipeline get dropped.
      _interruptedAt = DateTime.now();
    }
    // Clear accumulated text from the old mode so it doesn't leak
    // into a new turn in the new mode.
    _turnUserTexts.clear();
    _turnAiTexts.clear();
    _pendingAiText = '';
    state = AsyncData(
      current.copyWith(
        mode: newMode,
        isResponding: false,
        clearTranscript: true,
        clearUserTranscript: true,
        clearTranslation: true,
        clearAction: true,
        clearTutorStep: true,
        clearSupportTopic: true,
        clearExport: true,
        clearPhotoCapture: true,
      ),
    );
    // Only tell the backend if the user is actively streaming; changing modes
    // while idle should not trigger a Gemini reconnect on the backend.
    // Debounce rapid taps so only the LAST mode is sent after a brief pause.
    if (current.isStreaming) {
      _modeSwitchDebounce?.cancel();
      _modeSwitchDebounce = Timer(const Duration(milliseconds: 400), () {
        final latest = state.valueOrNull?.mode ?? newMode;
        if (_lastSentMode != latest) {
          final selectedVoice = ref.read(settingsProvider).selectedVoice;
          _ws?.send(
            WsInbound(
              type: 'set_mode',
              mode: latest.wsValue,
              voice: selectedVoice,
            ),
          );
          _lastSentMode = latest;
        }
      });
    }
  }

  void setLanguages({String? sourceLang, String? targetLang}) {
    final current = state.valueOrNull ?? const LiveSessionState();
    state = AsyncData(
      current.copyWith(sourceLang: sourceLang, targetLang: targetLang),
    );
    _ws?.send(
      WsInbound(
        type: 'set_language',
        sourceLang: sourceLang ?? current.sourceLang,
        targetLang: targetLang ?? current.targetLang,
      ),
    );
  }

  // ── Start / Stop ──────────────────────────────────────────────────────

  /// Pre-establish the WebSocket without starting audio.
  /// Call this from the Live screen's [initState] so the connection indicator
  /// turns green immediately when the tab opens.
  Future<void> connectOnly() async {
    final current = state.valueOrNull ?? const LiveSessionState();
    // Don't interrupt an existing connection or an active reconnect cycle.
    if (current.connectionState == WsConnectionState.connected ||
        current.connectionState == WsConnectionState.connecting ||
        (_ws != null && _ws!.isReconnecting)) {
      return;
    }
    _intentionalDisconnect = false;
    try {
      final userId = ref.read(userIdProvider);
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      // Dispose old WS to prevent zombie connections with running timers.
      _ws?.dispose();
      _ws = WebSocketService(
        userId: userId,
        authToken: token,
        tokenRefresher: () async =>
            FirebaseAuth.instance.currentUser?.getIdToken(true),
      );
      _stateSub?.cancel();
      _msgSub?.cancel();
      _stateSub = _ws!.stateStream.listen(_onWsStateChange);
      _msgSub = _ws!.messageStream.listen(_handleServerMessage);
      await _ws!.connect();
      // Create player eagerly so AI audio plays even before mic is started.
      _audio ??= AudioService();
      // Do NOT send set_mode here. Gemini must be connected fresh at the
      // exact moment audio starts flowing (in startSession). Pre-warming
      // creates a stale session that silently drops audio.
      _lastSentMode = null;
    } catch (e, st) {
      _log.severe('connectOnly failed', e, st);
      state = AsyncData(
        (state.valueOrNull ?? const LiveSessionState()).copyWith(
          connectionState: WsConnectionState.disconnected,
        ),
      );
    }
  }

  Future<void> startSession() async {
    final userId = ref.read(userIdProvider);
    final current = state.valueOrNull ?? const LiveSessionState();

    // Reuse existing WS if already connected via connectOnly()
    if (_ws == null || current.connectionState != WsConnectionState.connected) {
      // Dispose old WS to prevent resource leaks before creating a new one.
      _ws?.dispose();
      _ws = WebSocketService(
        userId: userId,
        authToken: await FirebaseAuth.instance.currentUser?.getIdToken(),
        tokenRefresher: () async =>
            FirebaseAuth.instance.currentUser?.getIdToken(true),
      );
      _stateSub?.cancel();
      _msgSub?.cancel();
      _stateSub = _ws!.stateStream.listen(_onWsStateChange);
      _msgSub = _ws!.messageStream.listen(_handleServerMessage);
      await _ws!.connect();
    }

    // Reuse or create AudioService (player + recorder in one)
    _audio ??= AudioService();
    // Clear interrupt guard so first audio chunk of new session isn't dropped.
    _interruptedAt = null;
    // When AI finishes speaking (playback complete), clear responding flag,
    // commit deferred AI text to chat, and ensure recorder is alive.
    _audio!.onPlaybackDone = () {
      _log.info('onPlaybackDone fired');
      final cur = state.valueOrNull ?? const LiveSessionState();
      final msgs = <ChatMessage>[...cur.chatMessages];
      // Commit the AI transcript now that the user has heard it.
      if (_pendingAiText.isNotEmpty) {
        msgs.add(ChatMessage(text: _pendingAiText));
        _pendingAiText = '';
      }
      state = AsyncData(cur.copyWith(
        isResponding: false,
        chatMessages: msgs,
        clearTranscript: true,
      ));
      // ALWAYS verify recorder health after playback finishes.
      // On some devices, audio focus shifting to the player during
      // playback silently kills the recorder stream.  ensureRecording()
      // checks data freshness (not just isCapturing) and restarts if stale.
      if (cur.isStreaming) {
        _audio?.ensureRecording();
      }
    };

    // ALWAYS send set_mode so the backend creates a Gemini session even
    // after a WS reconnect to a fresh Cloud Run instance.  The backend
    // handles duplicate set_mode cheaply (skips reconnect if same mode).
    final selectedVoice = ref.read(settingsProvider).selectedVoice;
    final resumeId = ref.read(resumeSessionProvider);
    _ws!.send(
      WsInbound(
        type: 'set_mode',
        mode: current.mode.wsValue,
        voice: selectedVoice,
        resumeSessionId: resumeId,
      ),
    );
    _lastSentMode = current.mode;
    // Clear resume after use
    if (resumeId != null) {
      ref.read(resumeSessionProvider.notifier).state = null;
    }

    // If translator, send language prefs
    if (current.mode == AgentMode.translator) {
      _ws!.send(
        WsInbound(
          type: 'set_language',
          sourceLang: current.sourceLang,
          targetLang: current.targetLang,
        ),
      );
    }

    // Cancel any live audio subscription first to avoid duplicate sends
    await _audioSub?.cancel();
    _audioSub = null;

    // Start audio capture and pipe to WebSocket.
    // If audio fails to start, tear down the Gemini session so the
    // backend doesn't keep an orphaned connection.
    try {
      await _audio!.start();
    } catch (e, st) {
      _log.severe('audio start failed — tearing down session', e, st);
      _ws?.send(const WsInbound(type: 'end_session'));
      state = AsyncData(current.copyWith(
        isStreaming: false,
        connectionState: WsConnectionState.disconnected,
      ));
      return;
    }
    _audioChunksSent = 0;
    _audioSub = _audio!.audioStream.listen(
      (b64) {
        // Only send audio when NOT muted.
        final cur = state.valueOrNull;
        if (cur != null && cur.isMuted) return;
        // ── ALWAYS forward mic audio (true bidirectional) ─────
        // Gemini Live API is designed for full-duplex. The mic must
        // always flow so the user can interrupt naturally by speaking.
        // Server-side VAD (LOW start sensitivity) prevents false
        // barge-ins from speaker echo. Hardware AEC (voiceChat mode)
        // further reduces echo on the device side.
        _audioChunksSent++;
        if (_audioChunksSent % 50 == 1) {
          _log.fine(
            'audio chunk #$_audioChunksSent → WS (state=${_ws?.state})',
          );
        }
        _ws?.send(WsInbound(type: 'audio', data: b64));
      },
      onDone: () {
        _log.warning(
          'audioStream DONE — subscription ended! chunks=$_audioChunksSent',
        );
      },
      onError: (e) {
        _log.severe('audioStream ERROR', e);
      },
    );

    // Pipe mic amplitude to the ValueNotifier for the orb visualizer.
    _ampSub?.cancel();
    _ampSub = _audio!.amplitudeStream.listen(
      (amp) {
        final cur = state.valueOrNull;
        // Show flat line when muted.
        amplitudeNotifier.value = (cur != null && cur.isMuted) ? 0.0 : amp;
      },
    );

    state = AsyncData(
      current.copyWith(
        isStreaming: true,
        isMuted: false, // Start listening immediately — one tap to go
        connectionState: WsConnectionState.connected,
      ),
    );

    // ── Start watchdog timers ─────────────────────────────────────────
    _startWatchdogs();
  }

  void _startWatchdogs() {
    _stopWatchdogs();

    // Recorder watchdog: every 3s check if audio chunks are flowing.
    _lastWatchdogChunkCount = _audioChunksSent;
    _watchdogStallCount = 0;
    _recorderWatchdog = Timer.periodic(const Duration(seconds: 3), (_) {
      final cur = state.valueOrNull;
      if (cur == null || !cur.isStreaming || cur.isMuted) {
        _lastWatchdogChunkCount = _audioChunksSent;
        _watchdogStallCount = 0;
        return;
      }
      if (_audioChunksSent == _lastWatchdogChunkCount) {
        _watchdogStallCount++;
        _log.warning(
          'Recorder watchdog: no new chunks for ${_watchdogStallCount * 3}s '
          '(total=$_audioChunksSent) — force-restarting recorder',
        );
        _audio?.ensureRecording();
      } else {
        _watchdogStallCount = 0;
      }
      _lastWatchdogChunkCount = _audioChunksSent;
    });

    // Response watchdog: every 4s check if user spoke but got no reply.
    _responseWatchdog = Timer.periodic(const Duration(seconds: 4), (_) {
      final cur = state.valueOrNull;
      if (cur == null || !cur.isStreaming || cur.isMuted) {
        _lastUserTranscriptAt = null;
        return;
      }
      // Targeted check: server confirmed user speech (via user_transcript)
      // but no AI response arrived within 8 seconds.  This catches the
      // common case where Gemini heard the user but then died/stalled.
      if (_lastUserTranscriptAt != null && !cur.isResponding) {
        final sinceSpoke =
            DateTime.now().difference(_lastUserTranscriptAt!).inSeconds;
        if (sinceSpoke >= 8) {
          _log.warning(
            'Response watchdog: user spoke ${sinceSpoke}s ago, no AI response '
            '— forcing session restart',
          );
          _lastUserTranscriptAt = null;
          _forceSessionRestart();
          return;
        }
      }
    });
  }

  void _stopWatchdogs() {
    _recorderWatchdog?.cancel();
    _recorderWatchdog = null;
    _responseWatchdog?.cancel();
    _responseWatchdog = null;
  }

  /// Tear down and restart the entire audio + Gemini session.
  Future<void> _forceSessionRestart() async {
    if (_restartInFlight) {
      _log.info('force restart ignored (already in flight)');
      return;
    }
    _restartInFlight = true;
    _log.warning('Force-restarting session');
    _stopWatchdogs();
    _turnCompleteTimer?.cancel();
    try {
      // Send discard_session so the backend does NOT persist the broken
      // session.  Previously this sent end_session which caused phantom
      // sessions to appear in the user's Archive.
      _ws?.send(const WsInbound(type: 'discard_session'));

      // Stop playback but KEEP the recorder running so the user's
      // audio continues to flow as soon as the new session starts.
      // Only cancel the data subscriptions (they are recreated in
      // startSession).
      await _audio?.stopPlayback();
      await _audioSub?.cancel();
      _audioSub = null;
      _ampSub?.cancel();
      _ampSub = null;

      // Clear accumulated turn texts so stale transcripts from the dying
      // session don't leak into the new one.
      _turnUserTexts.clear();
      _turnAiTexts.clear();
      _pendingAiText = '';
      _interruptedAt = null;
      _lastUserTranscriptAt = null;
      // Force _lastSentMode to null so startSession() sends a fresh set_mode.
      _lastSentMode = null;

      // Brief wait for backend to process the discard.
      await Future.delayed(const Duration(milliseconds: 300));

      // Restart — this sends a new set_mode which will create a fresh
      // Gemini session because end_session set session=None on the backend.
      // The recorder is still alive, so audio starts flowing immediately.
      await startSession();
    } finally {
      _restartInFlight = false;
    }
  }

  /// Toggle the microphone mute state. When muted, audio chunks are
  /// still captured but NOT forwarded to the backend.
  void toggleMute() {
    final current = state.valueOrNull ?? const LiveSessionState();
    if (!current.isStreaming) return;
    final newMuted = !current.isMuted;
    _log.info('toggleMute: isMuted=$newMuted');
    state = AsyncData(current.copyWith(isMuted: newMuted));
  }

  /// Explicitly interrupt the AI's current response (tap-to-interrupt).
  ///
  /// Stops playback, clears pending audio, commits partial transcript,
  /// and resumes mic forwarding so the user can speak. Sends END_TURN
  /// to signal Gemini that the user wants to talk.
  void interruptResponse() {
    final current = state.valueOrNull ?? const LiveSessionState();
    if (!current.isResponding) return;
    _log.info('user tap-to-interrupt');
    _turnCompleteTimer?.cancel();
    _interruptedAt = DateTime.now();
    _lastUserTranscriptAt = null;
    _responseStaleTimer?.cancel();

    // Commit partial texts
    final partialMsgs = <ChatMessage>[...current.chatMessages];
    final partialUser = _turnUserTexts.join(' ').trim();
    if (partialUser.isNotEmpty) {
      partialMsgs.add(ChatMessage(text: partialUser, isUser: true));
    }
    final partialAi = _turnAiTexts.join(' ').trim();
    if (partialAi.isNotEmpty) {
      final heard = partialAi.length > 80
          ? '${partialAi.substring(0, 80)}…'
          : '$partialAi…';
      partialMsgs.add(ChatMessage(text: heard));
    }
    _turnUserTexts.clear();
    _turnAiTexts.clear();
    _pendingAiText = '';

    // Stop playback immediately.
    unawaited(_audio?.stopPlayback() ?? Future.value());

    // Ensure recorder is alive for the next user utterance.
    if (current.isStreaming) {
      _audio?.ensureRecording();
    }

    state = AsyncData(
      current.copyWith(
        isResponding: false,
        clearTranscript: true,
        clearUserTranscript: true,
        clearTranslation: true,
        clearAction: true,
        clearTutorStep: true,
        clearExport: true,
        clearPhotoCapture: true,
        chatMessages: partialMsgs,
      ),
    );

    // Tell Gemini to end the current turn so it starts listening.
    _ws?.send(const WsInbound(type: 'end_turn'));
  }

  Future<void> stopSession({bool saveToArchive = true}) async {
    _intentionalDisconnect = true;
    _stopWatchdogs();
    _turnCompleteTimer?.cancel();

    // ── 1. Update state FIRST so UI shows idle immediately ──────────
    //    This prevents the "stuck on Listening" bug when async cleanup
    //    below hangs or throws.
    state = AsyncData(
      (state.valueOrNull ?? const LiveSessionState()).copyWith(
        isStreaming: false,
        isResponding: false,
        isMuted: true,
      ),
    );

    // ── 2. Async cleanup — wrapped in try-catch so state is never
    //    left inconsistent even if individual operations fail. ────────
    try {
      // Cancel the audio subscription before stopping capture to prevent
      // stale chunks being sent over a half-closed socket.
      await _audioSub?.cancel();
      _audioSub = null;
      _ampSub?.cancel();
      _ampSub = null;
      amplitudeNotifier.value = 0.0;
      await _audio?.stop();
      await _audio?.stopPlayback();
    } catch (e) {
      _log.warning('stopSession cleanup error (non-fatal): $e');
      // Force-null subscriptions even on error.
      _audioSub = null;
      _ampSub = null;
      amplitudeNotifier.value = 0.0;
    }

    // Tell the backend to save the session NOW (before WS teardown).
    if (saveToArchive) {
      try {
        _ws?.send(const WsInbound(type: 'end_session'));
      } catch (e) {
        _log.warning('stopSession end_session send error: $e');
      }
    } else {
      // Discard — send discard_session so backend doesn't save.
      try {
        _ws?.send(const WsInbound(type: 'discard_session'));
      } catch (e) {
        _log.warning('stopSession discard_session send error: $e');
      }
    }

    // Force _lastSentMode to null so the next startSession() always
    // sends set_mode — vital after WS reconnects to a fresh backend.
    _lastSentMode = null;
    // Re-establish the WS so the green indicator stays on.
    unawaited(connectOnly());
  }

  /// Send a video frame.
  void sendVideoFrame(String base64Jpeg) {
    _ws?.send(WsInbound(type: 'video', data: base64Jpeg));
  }

  /// Send a text query (typed input).
  void sendText(String text) {
    _ws?.send(WsInbound(type: 'text', text: text));
  }

  /// Dismiss current smart action card.
  void dismissAction() {
    final current = state.valueOrNull ?? const LiveSessionState();
    state = AsyncData(current.copyWith(clearAction: true));
  }

  /// Dismiss current tutor step (acknowledged).
  void dismissTutorStep() {
    final current = state.valueOrNull ?? const LiveSessionState();
    state = AsyncData(current.copyWith(clearTutorStep: true));
  }

  /// Dismiss pending export document card.
  void dismissExport() {
    final current = state.valueOrNull ?? const LiveSessionState();
    state = AsyncData(current.copyWith(clearExport: true));
  }

  /// Dismiss the post-session insights card.
  void dismissSessionInsights() {
    final current = state.valueOrNull ?? const LiveSessionState();
    state = AsyncData(current.copyWith(clearSessionInsights: true));
  }

  /// Clear pending photo capture request after the UI has consumed it.
  void clearPhotoCapture() {
    final current = state.valueOrNull ?? const LiveSessionState();
    state = AsyncData(current.copyWith(clearPhotoCapture: true));
  }

  void _scheduleTurnCompleteFinalize() {
    _turnCompleteTimer?.cancel();
    // Reduced to 80ms: just enough to catch any final audio chunk that
    // arrives in the same event-loop cycle as turn_complete, without
    // adding noticeable latency before the final flush plays.
    _turnCompleteTimer = Timer(const Duration(milliseconds: 80), () {
      final current = state.valueOrNull ?? const LiveSessionState();
      _log.info('finalizing turn_complete (debounced)');
      _audio?.flushAndPlay();

      final newMessages = <ChatMessage>[...current.chatMessages];
      // Commit user text immediately — the user already said it.
      final userText = _turnUserTexts.join(' ').trim();
      if (userText.isNotEmpty) {
        newMessages.add(ChatMessage(text: userText, isUser: true));
      }
      _turnUserTexts.clear();

      // Defer AI text until playback finishes so the text doesn't
      // spoil the audio. Store it for onPlaybackDone to commit.
      _pendingAiText = _turnAiTexts.join(' ').trim();
      _turnAiTexts.clear();

      state = AsyncData(
        current.copyWith(
          clearUserTranscript: true,
          chatMessages: newMessages,
        ),
      );
    });
  }

  // ── Message handling ──────────────────────────────────────────────────

  void _handleServerMessage(WsOutbound msg) {
    final current = state.valueOrNull ?? const LiveSessionState();
    _trackLatency(msg);
    // Track liveness of any non-pong message.
    if (msg.type != 'pong') {}

    switch (msg.type) {
      case 'audio':
        if (msg.data != null) {
          // Drop trailing audio that arrives right after an interruption.
          // These are chunks that were already in the WebSocket buffer when
          // the server detected the barge-in. Playing them would cause the
          // user to hear old-response audio after they interrupted.
          // IMPORTANT: Keep this window VERY short (50ms). Gemini's new
          // response audio arrives within 300-500ms of the interrupt.
          // A longer window (e.g. 500ms) drops the first words of the
          // NEW response, causing "text shows but audio doesn't match."
          if (_interruptedAt != null) {
            final msSinceInterrupt =
                DateTime.now().difference(_interruptedAt!).inMilliseconds;
            if (msSinceInterrupt < 50) {
              break; // silently drop trailing chunk
            }
            _interruptedAt = null; // grace window elapsed
          }
          // If turn_complete just arrived, allow this trailing audio to be
          // included before finalizing playback.
          if (_turnCompleteTimer != null && _turnCompleteTimer!.isActive) {
            _scheduleTurnCompleteFinalize();
          }
          // Late chunks after turn_complete timer already fired:
          // just queue them. The audio_service playback loop's
          // demand-flush handles them automatically.
          _audio?.queueChunk(msg.data!);
          // Mark as responding for UI.
          // Mic audio forwarding is paused while isResponding (echo
          // suppression). The user can tap the orb to interrupt.
          if (!current.isResponding) {
            // AI started responding — clear the user-spoke tracker so the
            // response watchdog doesn't fire.
            _lastUserTranscriptAt = null;
            _log.info('first audio chunk received — setting isResponding=true');
            HapticFeedback.selectionClick();
            state = AsyncData(
              current.copyWith(isResponding: true, clearUserTranscript: true),
            );
          }
          // Reset the response stale timer. If no new audio chunk arrives
          // within 8 seconds, auto-finalize the turn to prevent the client
          // from being stuck in isResponding=true forever.
          _responseStaleTimer?.cancel();
          _responseStaleTimer = Timer(const Duration(seconds: 8), () {
            _responseStaleTimer = null;
            final cur = state.valueOrNull;
            if (cur != null && cur.isResponding) {
              _log.warning(
                'response stale timer fired — no audio for 15s, auto-finalizing',
              );
              _audio?.flushAndPlay();
            }
          });
        }
        break;

      case 'transcript':
        if (msg.text != null && msg.text!.isNotEmpty) {
          _turnAiTexts.add(msg.text!);
          // Show live transcript so the user can follow along while
          // the AI speaks.  The text may run a bit ahead of audio —
          // this is normal (like subtitles).  The full text is
          // committed to chat history in onPlaybackDone.
          state = AsyncData(
            current.copyWith(
              transcript: _turnAiTexts.join(' '),
            ),
          );
        }
        break;

      case 'user_transcript':
        if (msg.text != null && msg.text!.isNotEmpty) {
          _turnUserTexts.add(msg.text!);
          // Record when the server confirmed user speech — used by the
          // response watchdog to detect if Gemini heard but never replied.
          _lastUserTranscriptAt = DateTime.now();
        }
        // Show accumulated user text for a readable live bubble.
        state = AsyncData(
          current.copyWith(userTranscript: _turnUserTexts.join(' ')),
        );
        break;

      case 'ui_action':
        final action = SmartAction.fromPayload(
          msg.actionType ?? 'generic',
          msg.payload ?? {},
        );
        state = AsyncData(
          current.copyWith(
            currentAction: action,
            actionHistory: [...current.actionHistory, action],
          ),
        );
        break;

      case 'capture_photo':
        final desc = msg.payload?['description'] as String? ?? '';
        _log.info('capture_photo requested: $desc');
        state = AsyncData(
          current.copyWith(pendingPhotoCapture: desc.isEmpty ? 'photo' : desc),
        );
        break;

      case 'translation':
        if (msg.payload != null) {
          final overlay = TranslationOverlay.fromPayload(msg.payload!);
          state = AsyncData(
            current.copyWith(
              currentTranslation: overlay,
              translationHistory: [...current.translationHistory, overlay],
            ),
          );
        }
        break;

      case 'tutor_step':
        if (msg.payload != null) {
          final step = TutorStep.fromPayload(msg.payload!);
          state = AsyncData(
            current.copyWith(
              currentTutorStep: step,
              tutorSteps: [...current.tutorSteps, step],
            ),
          );
        }
        break;

      case 'support_topic':
        if (msg.payload != null) {
          final topic = SupportTopic.fromPayload(msg.payload!);
          state = AsyncData(
            current.copyWith(
              currentSupportTopic: topic,
              supportTopics: [...current.supportTopics, topic],
            ),
          );
        }
        break;

      case 'export':
        if (msg.payload != null) {
          final doc = ExportDocument.fromPayload(msg.payload!);
          state = AsyncData(current.copyWith(pendingExport: doc));
        }
        break;

      case 'note_saved':
        _log.info('Note saved: ${msg.payload?['title']}');
        HapticFeedback.heavyImpact();
        _notesSavedThisSession++;
        // The note is already persisted in Firestore by the backend.
        // Show a confirmation card via SmartAction.
        final action = SmartAction.fromPayload('save_note', {
          'title': 'Note Saved',
          'description': msg.payload?['title'] ?? 'Note saved',
          'icon': (msg.payload?['isTodo'] == true) ? 'check_box' : 'note',
          'primary_action_label': 'View Notes',
        });
        state = AsyncData(
          current.copyWith(
            currentAction: action,
            actionHistory: [...current.actionHistory, action],
          ),
        );
        break;

      case 'reminder_set':
        _log.info('Reminder set: ${msg.payload?['title']}');
        HapticFeedback.heavyImpact();
        // Schedule local notification
        if (msg.payload != null) {
          final reminder = ReminderModel.fromPayload(msg.payload!);
          scheduleReminderNotification(reminder);
          // Show confirmation card
          final action = SmartAction.fromPayload('add_reminder', {
            'title': 'Reminder Set',
            'description':
                '${msg.payload?['title']} — in ${msg.payload?['remindInMinutes']} min',
            'icon': 'alarm',
            'primary_action_label': 'View Reminders',
          });
          state = AsyncData(
            current.copyWith(
              currentAction: action,
              actionHistory: [...current.actionHistory, action],
            ),
          );
        }
        break;

      case 'mode_changed':
        final newModeStr = msg.text ?? 'general';
        final newMode = AgentMode.values.firstWhere(
          (m) => m.name == newModeStr,
          orElse: () => AgentMode.general,
        );
        // Clear stale mode-specific UI overlays when switching modes
        // to avoid showing e.g. a translation card in tutor mode.
        state = AsyncData(current.copyWith(
          mode: newMode,
          clearTranslation: true,
          clearTutorStep: true,
          clearSupportTopic: true,
          clearAction: true,
        ));
        break;

      case 'turn_complete':
        _log.info('turn_complete received from backend (debounced)');
        _lastUserTranscriptAt = null;
        _responseStaleTimer?.cancel();
        _scheduleTurnCompleteFinalize();
        break;

      case 'interrupted':
        // User barged in — stop playback and restart mic IMMEDIATELY so
        // Gemini keeps hearing the user’s speech and can pivot its response.
        _log.info('interrupted received from backend');
        _turnCompleteTimer?.cancel();
        _responseStaleTimer?.cancel();
        _interruptedAt = DateTime.now();
        _lastUserTranscriptAt = null;
        // Commit partial USER text (what they said before the interrupt).
        // Do NOT commit the AI’s full accumulated text — the user only
        // heard part of it as audio; showing the full transcript is misleading.
        final partialMsgs = <ChatMessage>[...current.chatMessages];
        final partialUser = _turnUserTexts.join(' ').trim();
        if (partialUser.isNotEmpty) {
          partialMsgs.add(ChatMessage(text: partialUser, isUser: true));
        }
        // Only show a truncated version of what the user actually heard.
        final partialAi = _turnAiTexts.join(' ').trim();
        if (partialAi.isNotEmpty) {
          final heard = partialAi.length > 80
              ? '${partialAi.substring(0, 80)}…'
              : '$partialAi…';
          partialMsgs.add(ChatMessage(text: heard));
        }
        _turnUserTexts.clear();
        _turnAiTexts.clear();
        _pendingAiText = '';

        // Fire-and-forget playback stop — don’t block on it.
        unawaited(_audio?.stopPlayback() ?? Future.value());

        // IMMEDIATELY restart recorder so Gemini keeps receiving audio.
        // With single-player architecture, audio focus stays stable —
        // no delay needed. The recorder should still be alive since we
        // never dispose it, but verify just in case.
        if (current.isStreaming) {
          _log.info('ensuring recorder alive after barge-in');
          _audio?.ensureRecording();
        }

        state = AsyncData(
          current.copyWith(
            isResponding: false,
            clearTranscript: true,
            clearUserTranscript: true,
            clearTranslation: true,
            clearAction: true,
            clearTutorStep: true,
            clearExport: true,
            clearPhotoCapture: true,
            chatMessages: partialMsgs,
          ),
        );
        break;

      case 'status':
        // Handle voice switch notification from backend
        if (msg.text != null && msg.text!.startsWith('voice:')) {
          final newVoice = msg.text!.substring(6); // strip 'voice:'
          _log.info('Voice switched to: $newVoice');
          ref.read(settingsProvider.notifier).setVoice(newVoice);
        }
        break;
      case 'pong':
        break;

      case 'session_saved':
        _log.info('Session saved by backend');
        HapticFeedback.lightImpact();
        // Build post-session insights card from the payload.
        final insights = SessionInsights(
          sessionId: msg.payload?['session_id'] as String? ?? '',
          title: msg.payload?['title'] as String? ?? 'Session Complete',
          summary: msg.payload?['summary'] as String? ?? '',
          turnCount: (msg.payload?['turn_count'] as num?)?.toInt() ?? 0,
          notesSaved: _notesSavedThisSession,
          topics: (msg.payload?['topics'] as List<dynamic>?)
                  ?.whereType<String>()
                  .toList() ??
              [],
          mode: current.mode,
        );
        _notesSavedThisSession = 0;
        state = AsyncData(
          current.copyWith(sessionInsights: insights),
        );
        // Refresh the session list so the Archive tab shows the new session.
        ref.invalidate(sessionListProvider);
        break;

      case 'error':
        // Log but do NOT set AsyncError — that destroys the entire session
        // state (mode, streaming, connection). Recoverable errors (mode switch
        // failed, AI temporarily unavailable) should be surfaced as a SnackBar
        // without tearing down the session.
        _log.warning('Server error: ${msg.text}');
        // Add as system message in chat so the user sees it.
        if (msg.text != null && msg.text!.isNotEmpty) {
          final msgs = <ChatMessage>[...current.chatMessages];
          msgs.add(ChatMessage(text: msg.text!, isSystem: true));
          state = AsyncData(current.copyWith(chatMessages: msgs));
        }
        break;
    }
  }

  void _cleanup() {
    _stopWatchdogs();
    _msgSub?.cancel();
    _stateSub?.cancel();
    _audioSub?.cancel();
    _ampSub?.cancel();
    _modeSwitchDebounce?.cancel();
    _turnCompleteTimer?.cancel();
    _responseStaleTimer?.cancel();
    amplitudeNotifier.dispose();
    _ws?.dispose();
    _audio?.dispose();
  }
}

final liveSessionProvider =
    AutoDisposeAsyncNotifierProvider<LiveSessionNotifier, LiveSessionState>(
  LiveSessionNotifier.new,
);
