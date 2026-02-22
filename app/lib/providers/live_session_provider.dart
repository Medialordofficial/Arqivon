import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_mode.dart';
import '../models/smart_action.dart';
import '../models/ws_message.dart';
import '../services/audio_service.dart';
import '../services/websocket_service.dart';
import 'auth_provider.dart';

/// Exposed live session state.
class LiveSessionState {
  final WsConnectionState connectionState;
  final bool isStreaming;

  /// True while Gemini is streaming audio back to the user.
  final bool isResponding;
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

  const LiveSessionState({
    this.connectionState = WsConnectionState.disconnected,
    this.isStreaming = false,
    this.isResponding = false,
    this.mode = AgentMode.general,
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
  });

  LiveSessionState copyWith({
    WsConnectionState? connectionState,
    bool? isStreaming,
    bool? isResponding,
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
    List<SupportTopic>? supportTopics,
  }) {
    return LiveSessionState(
      connectionState: connectionState ?? this.connectionState,
      isStreaming: isStreaming ?? this.isStreaming,
      isResponding: isResponding ?? this.isResponding,
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
      currentSupportTopic: currentSupportTopic ?? this.currentSupportTopic,
      supportTopics: supportTopics ?? this.supportTopics,
    );
  }
}

/// The core Live session provider managing WebSocket + audio pipeline.
class LiveSessionNotifier extends AutoDisposeAsyncNotifier<LiveSessionState> {
  WebSocketService? _ws;
  AudioCaptureService? _audio;
  StreamSubscription? _msgSub;
  StreamSubscription? _stateSub;
  int _audioChunksSent = 0;

  StreamSubscription? _audioSub;
  // Track which mode was last sent to the backend so we avoid triggering an
  // unnecessary Gemini session restart on every mic tap.
  AgentMode? _lastSentMode;

  @override
  Future<LiveSessionState> build() async {
    ref.onDispose(_cleanup);
    return const LiveSessionState();
  }

  // ── Mode Management ───────────────────────────────────────────────────

  void setMode(AgentMode newMode) {
    final current = state.valueOrNull ?? const LiveSessionState();
    state = AsyncData(current.copyWith(mode: newMode));
    // Only tell the backend if the user is actively streaming; changing modes
    // while idle should not trigger a Gemini reconnect on the backend.
    if (current.isStreaming) {
      _ws?.send(WsInbound(type: 'set_mode', mode: newMode.wsValue));
    }
  }

  void setLanguages({String? sourceLang, String? targetLang}) {
    final current = state.valueOrNull ?? const LiveSessionState();
    state = AsyncData(current.copyWith(
      sourceLang: sourceLang,
      targetLang: targetLang,
    ));
    _ws?.send(WsInbound(
      type: 'set_language',
      sourceLang: sourceLang ?? current.sourceLang,
      targetLang: targetLang ?? current.targetLang,
    ));
  }

  // ── Start / Stop ──────────────────────────────────────────────────────

  /// Pre-establish the WebSocket without starting audio.
  /// Call this from the Live screen's [initState] so the connection indicator
  /// turns green immediately when the tab opens.
  Future<void> connectOnly() async {
    final current = state.valueOrNull ?? const LiveSessionState();
    if (current.connectionState == WsConnectionState.connected ||
        current.connectionState == WsConnectionState.connecting) return;
    final userId = ref.read(userIdProvider);
    _ws = WebSocketService(userId: userId);
    _stateSub?.cancel();
    _msgSub?.cancel();
    _stateSub = _ws!.stateStream.listen((s) {
      final cur = state.valueOrNull ?? const LiveSessionState();
      state = AsyncData(cur.copyWith(connectionState: s));
    });
    _msgSub = _ws!.messageStream.listen(_handleServerMessage);
    await _ws!.connect();
    // Create player eagerly so AI audio plays even before mic is started.
    _audio ??= AudioService();
    // NOTE: do NOT send set_mode here — that forces a Gemini reconnect before
    // the user has started speaking and causes the second set_mode from
    // startSession() to race against it, resulting in silence.
    // Reset mode tracking so first startSession() will send the correct mode.
    _lastSentMode = null;
  }

  Future<void> startSession() async {
    final userId = ref.read(userIdProvider);
    final current = state.valueOrNull ?? const LiveSessionState();

    // Reuse existing WS if already connected via connectOnly()
    if (_ws == null || current.connectionState != WsConnectionState.connected) {
      _ws = WebSocketService(userId: userId);
      _stateSub?.cancel();
      _msgSub?.cancel();
      _stateSub = _ws!.stateStream.listen((s) {
        final cur = state.valueOrNull ?? const LiveSessionState();
        state = AsyncData(cur.copyWith(connectionState: s));
      });
      _msgSub = _ws!.messageStream.listen(_handleServerMessage);
      await _ws!.connect();
    }

    // Reuse or create AudioService (player + recorder in one)
    _audio ??= AudioService();
    // When AI finishes speaking (playback complete), clear responding flag
    // and ensure the recorder is still alive for the next turn.
    _audio!.onPlaybackDone = () {
      print('[ARQIVO] onPlaybackDone fired');
      final cur = state.valueOrNull ?? const LiveSessionState();
      if (cur.isResponding) {
        state = AsyncData(cur.copyWith(isResponding: false));
      }
      // CRITICAL: explicitly restart recorder if it died during playback.
      // Android may kill the mic when audio focus changes.
      if (cur.isStreaming) {
        print('[ARQIVO] calling ensureRecording after playback done');
        _audio?.ensureRecording();
      }
    };

    // Only send set_mode when the mode changes so the backend does NOT tear
    // down and rebuild the Gemini Live session on every mic tap.  On the very
    // first tap after connectOnly() the mode will differ (null vs actual), so
    // we always send it at least once per connection.
    if (_lastSentMode != current.mode) {
      _ws!.send(WsInbound(type: 'set_mode', mode: current.mode.wsValue));
      _lastSentMode = current.mode;
    }

    // If translator, send language prefs
    if (current.mode == AgentMode.translator) {
      _ws!.send(WsInbound(
        type: 'set_language',
        sourceLang: current.sourceLang,
        targetLang: current.targetLang,
      ));
    }

    // Cancel any live audio subscription first to avoid duplicate sends
    await _audioSub?.cancel();
    _audioSub = null;

    // Start audio capture and pipe to WebSocket
    await _audio!.start();
    _audioChunksSent = 0;
    _audioSub = _audio!.audioStream.listen((b64) {
      _audioChunksSent++;
      if (_audioChunksSent % 50 == 1) {
        print(
            '[ARQIVO] audio chunk #$_audioChunksSent → WS (state=${_ws?.state})');
      }
      _ws?.send(WsInbound(type: 'audio', data: b64));
    }, onDone: () {
      print(
          '[ARQIVO] *** audioStream DONE — subscription ended! chunks=$_audioChunksSent');
    }, onError: (e) {
      print('[ARQIVO] *** audioStream ERROR: $e');
    });

    state = AsyncData(current.copyWith(
      isStreaming: true,
      connectionState: WsConnectionState.connected,
    ));
  }

  Future<void> stopSession() async {
    // Cancel the audio subscription before stopping capture to prevent stale
    // chunks being sent over a half-closed socket.
    await _audioSub?.cancel();
    _audioSub = null;
    await _audio?.stop();
    await _audio?.stopPlayback();
    state = AsyncData(
      (state.valueOrNull ?? const LiveSessionState()).copyWith(
        isStreaming: false,
        isResponding: false,
      ),
    );
    // Re-establish the WS so the green indicator stays on.
    // Keep _lastSentMode intact so if user re-taps mic (same mode) we do not
    // send another set_mode and force an unnecessary Gemini reconnect.
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

  // ── Message handling ──────────────────────────────────────────────────

  void _handleServerMessage(WsOutbound msg) {
    final current = state.valueOrNull ?? const LiveSessionState();

    switch (msg.type) {
      case 'audio':
        if (msg.data != null) {
          _audio?.queueChunk(msg.data!);
          // Mark as responding for UI (but mic stays active for barge-in).
          if (!current.isResponding) {
            print(
                '[ARQIVO] first audio chunk received — setting isResponding=true');
            state = AsyncData(current.copyWith(
              isResponding: true,
              clearUserTranscript: true,
            ));
          }
        }
        break;

      case 'transcript':
        state = AsyncData(current.copyWith(transcript: msg.text));
        break;

      case 'user_transcript':
        state = AsyncData(current.copyWith(userTranscript: msg.text));
        break;

      case 'ui_action':
        final action = SmartAction.fromPayload(
          msg.actionType ?? 'generic',
          msg.payload ?? {},
        );
        state = AsyncData(current.copyWith(
          currentAction: action,
          actionHistory: [...current.actionHistory, action],
        ));
        break;

      case 'translation':
        if (msg.payload != null) {
          final overlay = TranslationOverlay.fromPayload(msg.payload!);
          state = AsyncData(current.copyWith(
            currentTranslation: overlay,
            translationHistory: [...current.translationHistory, overlay],
          ));
        }
        break;

      case 'tutor_step':
        if (msg.payload != null) {
          final step = TutorStep.fromPayload(msg.payload!);
          state = AsyncData(current.copyWith(
            currentTutorStep: step,
            tutorSteps: [...current.tutorSteps, step],
          ));
        }
        break;

      case 'support_topic':
        if (msg.payload != null) {
          final topic = SupportTopic.fromPayload(msg.payload!);
          state = AsyncData(current.copyWith(
            currentSupportTopic: topic,
            supportTopics: [...current.supportTopics, topic],
          ));
        }
        break;

      case 'mode_changed':
        final newModeStr = msg.text ?? 'general';
        final newMode = AgentMode.values.firstWhere(
          (m) => m.name == newModeStr,
          orElse: () => AgentMode.general,
        );
        state = AsyncData(current.copyWith(mode: newMode));
        break;

      case 'turn_complete':
        // Flush remaining audio to the streaming queue.
        // isResponding stays true until playback actually finishes
        // (handled by onPlaybackDone callback).
        print('[ARQIVO] turn_complete received from backend');
        _audio?.flushAndPlay();
        state = AsyncData(current.copyWith(
          clearTranscript: true,
          clearUserTranscript: true,
        ));
        break;

      case 'interrupted':
        // User barged in — stop playback immediately and clear stale overlays.
        print('[ARQIVO] interrupted received from backend');
        _audio?.stopPlayback();
        state = AsyncData(current.copyWith(
          isResponding: false,
          clearTranslation: true,
        ));
        break;

      case 'status':
      case 'pong':
        break;

      case 'error':
        state = AsyncError(msg.text ?? 'Unknown error', StackTrace.current);
        break;
    }
  }

  void _cleanup() {
    _msgSub?.cancel();
    _stateSub?.cancel();
    _audioSub?.cancel();
    _ws?.dispose();
    _audio?.dispose();
  }
}

final liveSessionProvider =
    AutoDisposeAsyncNotifierProvider<LiveSessionNotifier, LiveSessionState>(
  LiveSessionNotifier.new,
);
