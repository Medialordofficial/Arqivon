import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/constants.dart';
import '../config/logger.dart';
import '../main.dart';
import '../models/agent_mode.dart';
import '../providers/live_session_provider.dart';
import '../services/action_handler_service.dart';
import '../services/websocket_service.dart';
import '../widgets/live_wave.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/mode_selector.dart';
import '../widgets/smart_action_card.dart';
import '../widgets/support_topic_tracker.dart';
import '../widgets/translation_overlay.dart';
import '../widgets/tutor_guidance_card.dart';
import '../widgets/export_document_card.dart';

enum _LiveInputMode { audioOnly, audioVideo }

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key, required this.tabNotifier});

  /// Notifier from [MainNavigator] that fires when the bottom tab changes.
  final TabIndexNotifier tabNotifier;

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen>
    with WidgetsBindingObserver {
  static final _log = AppLogger('LiveScreen');

  CameraController? _cameraController;
  Timer? _frameTimer;
  bool _cameraReady = false;
  final TextEditingController _textController = TextEditingController();
  bool _showTextInput = false;
  _LiveInputMode _inputMode = _LiveInputMode.audioOnly;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Stop audio/video when user navigates away from the Live tab.
    widget.tabNotifier.addListener(_onTabChanged);
    // Camera init deferred to when audio+video mode is selected.
    // WebSocket pre-connect: runs on first frame only (not at app startup
    // since MainNavigator now lazy-builds this screen).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(liveSessionProvider.notifier).connectOnly();
    });
  }

  void _onTabChanged() {
    if (widget.tabNotifier.index != 1) {
      // User navigated away from Live tab — stop session.
      final current = ref.read(liveSessionProvider).valueOrNull;
      if (current?.isStreaming ?? false) {
        _stopFrameCapture();
        ref.read(liveSessionProvider.notifier).stopSession();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false, // we record audio separately
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      _log.severe('Camera init error', e);
    }
  }

  void _startFrameCapture() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(
      AppConstants.frameCaptureInterval,
      (_) => _captureAndSendFrame(),
    );
  }

  void _stopFrameCapture() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  Future<void> _captureAndSendFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      final file = await _cameraController!.takePicture();
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      ref.read(liveSessionProvider.notifier).sendVideoFrame(b64);
    } catch (e) {
      // Frame drop is OK – don't crash
    }
  }

  Future<void> _toggleSession() async {
    final notifier = ref.read(liveSessionProvider.notifier);
    final current = ref.read(liveSessionProvider).valueOrNull;
    final isStreaming = current?.isStreaming ?? false;

    if (isStreaming) {
      _stopFrameCapture();
      await notifier.stopSession();
    } else {
      // Check microphone permission before starting
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        if (mounted) {
          final openSettings = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Microphone Required'),
              content: const Text(
                'Arqivon needs microphone access to have a voice conversation. '
                'Please grant microphone permission in Settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          if (openSettings == true) openAppSettings();
        }
        return;
      }
      await notifier.startSession();
      // Only stream video frames in A/V mode
      if (_inputMode == _LiveInputMode.audioVideo) {
        _startFrameCapture();
      }
    }
  }

  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    ref.read(liveSessionProvider.notifier).sendText(text);
    _textController.clear();
    setState(() => _showTextInput = false);
  }

  @override
  void dispose() {
    widget.tabNotifier.removeListener(_onTabChanged);
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _cameraController?.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(liveSessionProvider);

    // Show error SnackBar when session enters AsyncError state.
    ref.listen<AsyncValue<LiveSessionState>>(liveSessionProvider, (prev, next) {
      if (next is AsyncError && prev is! AsyncError) {
        final errMsg = next.error?.toString() ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Theme.of(context).colorScheme.onError,
              onPressed: () {
                ref.read(liveSessionProvider.notifier).connectOnly();
              },
            ),
          ),
        );
      }
    });

    final session = sessionAsync.valueOrNull;
    final isStreaming = session?.isStreaming ?? false;
    final isResponding = session?.isResponding ?? false;
    final connectionState =
        session?.connectionState ?? WsConnectionState.disconnected;
    final currentAction = session?.currentAction;
    final transcript = session?.transcript;
    final userTranscript = session?.userTranscript;
    final mode = session?.mode ?? AgentMode.general;
    final currentTranslation = session?.currentTranslation;
    final currentTutorStep = session?.currentTutorStep;
    final currentSupportTopic = session?.currentSupportTopic;
    final supportTopics = session?.supportTopics ?? [];
    final pendingExport = session?.pendingExport;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background ──────────────────────────────────────────
          if (_inputMode == _LiveInputMode.audioVideo &&
              _cameraReady &&
              _cameraController != null)
            ClipRRect(
              child: CameraPreview(_cameraController!),
            )
          else
            // Theme-aware background
            Container(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),

          // ── Gradient scrim (camera mode only) ─────────────────────
          if (_inputMode == _LiveInputMode.audioVideo)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    stops: const [0, 0.2, 0.55, 1.0],
                  ),
                ),
              ),
            ),

          // ── Bottom fade scrim (always) ─────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Theme.of(context)
                        .scaffoldBackgroundColor
                        .withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
          ),

          // ── Top bar: connection + LIVE badge ───────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                ConnectionIndicator(state: connectionState),
                const Spacer(),
                if (isStreaming)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fiber_manual_record,
                            size: 10, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          mode.label.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Mode selector strip ────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 44,
            left: 0,
            right: 0,
            child: ModeSelectorStrip(
              selectedMode: mode,
              isStreaming: isStreaming,
              onModeSelected: (m) {
                ref.read(liveSessionProvider.notifier).setMode(m);
              },
            ),
          ),

          // ── Translator: live translation subtitle ──────────────────
          if (mode == AgentMode.translator && currentTranslation != null)
            Positioned(
              top: MediaQuery.of(context).padding.top +
                  (transcript != null && transcript.isNotEmpty ? 170 : 94),
              left: 0,
              right: 0,
              child: TranslationOverlayWidget(
                overlay: currentTranslation,
              ),
            ),

          // ── Support: topic tracker ──────────────────────────────────
          if (mode == AgentMode.support && currentSupportTopic != null)
            Positioned(
              top: MediaQuery.of(context).padding.top +
                  (transcript != null && transcript.isNotEmpty ? 170 : 94),
              left: 0,
              right: 0,
              child: SupportTopicTracker(
                currentTopic: currentSupportTopic,
                allTopics: supportTopics,
              ),
            ),

          // ── Smart Action Card overlay ───────────────────────────────
          if (currentAction != null)
            Positioned(
              bottom: 220,
              left: 0,
              right: 0,
              child: SmartActionCard(
                action: currentAction,
                onDismiss: () =>
                    ref.read(liveSessionProvider.notifier).dismissAction(),
                onPrimaryAction: () async {
                  HapticFeedback.mediumImpact();
                  ref.read(liveSessionProvider.notifier).dismissAction();
                  final result = await ActionHandlerService.execute(
                    currentAction,
                    context,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(result),
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
              ),
            ),

          // ── Tutor: guidance card ────────────────────────────────────
          if (mode == AgentMode.tutor && currentTutorStep != null)
            Positioned(
              bottom: 220,
              left: 0,
              right: 0,
              child: TutorGuidanceCard(
                step: currentTutorStep,
                onDismiss: () =>
                    ref.read(liveSessionProvider.notifier).dismissTutorStep(),
                onRequestHint: () {
                  ref
                      .read(liveSessionProvider.notifier)
                      .sendText('Can you give me a hint for the current step?');
                },
              ),
            ),

          // ── Export: document export card ────────────────────────────
          if (pendingExport != null)
            Positioned(
              bottom: 220,
              left: 0,
              right: 0,
              child: ExportDocumentCard(
                doc: pendingExport,
                onDismiss: () =>
                    ref.read(liveSessionProvider.notifier).dismissExport(),
              ),
            ),

          // ── User speech (above orb) ───────────────────────────
          if (userTranscript != null && userTranscript.isNotEmpty)
            Positioned(
              left: 32,
              right: 32,
              top: MediaQuery.of(context).padding.top + 100,
              child: Text(
                userTranscript,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.50),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),

          // ── Centered orb — always visible ─────────────────────────
          Positioned.fill(
            child: Align(
              alignment: const Alignment(0, -0.20),
              child: LiveWave(
                isListening: isStreaming && !isResponding,
                isResponding: isResponding,
                color: mode.color,
                size: 270,
              ),
            ),
          ),

          // ── Idle prompt / transcript beneath orb ───────────────────
          Positioned(
            left: 24,
            right: 24,
            bottom: 190,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (transcript != null && transcript.isNotEmpty)
                  Text(
                    transcript,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      letterSpacing: -0.3,
                    ),
                  )
                else
                  Text(
                    isResponding
                        ? 'Responding…'
                        : isStreaming
                            ? 'Listening…'
                            : 'Go ahead, I\'m ready to assist',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isResponding
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.85)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.50),
                      fontSize: 16,
                      fontWeight:
                          isResponding ? FontWeight.w500 : FontWeight.w400,
                      letterSpacing: 0.1,
                    ),
                  ),
              ],
            ),
          ),

          // ── Bottom area: mic + text input ──────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Input mode toggle pill
                if (!isStreaming)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.10),
                          width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _InputModeChip(
                          label: 'Audio',
                          icon: Icons.mic_rounded,
                          selected: _inputMode == _LiveInputMode.audioOnly,
                          onTap: () => setState(
                              () => _inputMode = _LiveInputMode.audioOnly),
                        ),
                        const SizedBox(width: 4),
                        _InputModeChip(
                          label: 'Audio + Video',
                          icon: Icons.videocam_rounded,
                          selected: _inputMode == _LiveInputMode.audioVideo,
                          onTap: () {
                            setState(
                                () => _inputMode = _LiveInputMode.audioVideo);
                            // Init camera on first switch to A/V mode.
                            if (!_cameraReady) _initCamera();
                          },
                        ),
                      ],
                    ),
                  ),

                // Side controls + mic button row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Camera flip (A/V mode) or mode indicator
                    _controlButton(
                      icon: _inputMode == _LiveInputMode.audioVideo
                          ? Icons.flip_camera_ios_rounded
                          : mode.icon,
                      semanticLabel: _inputMode == _LiveInputMode.audioVideo
                          ? 'Flip camera'
                          : '${mode.label} mode',
                      onPressed: _inputMode == _LiveInputMode.audioVideo
                          ? () async {
                              final cameras = await availableCameras();
                              if (cameras.length < 2) return;
                              final current = _cameraController?.description;
                              final next = cameras.firstWhere(
                                (c) =>
                                    c.lensDirection != current?.lensDirection,
                                orElse: () => cameras.first,
                              );
                              // Pause frame capture to prevent race condition
                              _stopFrameCapture();
                              await _cameraController?.dispose();
                              _cameraController = CameraController(
                                next,
                                ResolutionPreset.medium,
                                enableAudio: false,
                              );
                              await _cameraController!.initialize();
                              if (mounted) {
                                setState(() {});
                                // Resume frame capture if streaming
                                final isCurrentlyStreaming = ref.read(liveSessionProvider).valueOrNull?.isStreaming ?? false;
                                if (isCurrentlyStreaming) _startFrameCapture();
                              }
                            }
                          : null, // mode icon is decorative in audio-only
                    ),

                    // ── Main mic / stop button ──────────────────────
                    Semantics(
                      label:
                          isStreaming ? 'Stop session' : 'Start live session',
                      button: true,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.heavyImpact();
                          _toggleSession();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isResponding
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF00BCD4),
                                      Color(0xFF7C3AED)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : isStreaming
                                    ? null
                                    : const LinearGradient(
                                        colors: [
                                          Color(0xFF7C3AED),
                                          Color(0xFF5B5FEF),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                            color: !isResponding && isStreaming
                                ? Colors.red
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: (isResponding
                                        ? const Color(0xFF00BCD4)
                                        : isStreaming
                                            ? Colors.red
                                            : const Color(0xFF5B5FEF))
                                    .withValues(alpha: 0.50),
                                blurRadius: 28,
                                spreadRadius: 6,
                              ),
                            ],
                          ),
                          child: Icon(
                            isResponding
                                ? Icons.record_voice_over_rounded
                                : isStreaming
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    // Keyboard toggle (right side)
                    _controlButton(
                      icon: Icons.keyboard_rounded,
                      semanticLabel:
                          _showTextInput ? 'Hide keyboard' : 'Show keyboard',
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() => _showTextInput = !_showTextInput);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── Text input field ─────────────────────────────────
                AnimatedCrossFade(
                  firstChild: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: Theme.of(context).dividerColor, width: 1),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 18),
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              maxLength: 500,
                              maxLines: 1,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 15),
                              decoration: InputDecoration(
                                hintText: _hintTextForMode(mode),
                                hintStyle: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.40),
                                    fontSize: 15),
                                border: InputBorder.none,
                                isDense: true,
                                counterText: '',
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onSubmitted: (_) => _sendTextMessage(),
                            ),
                          ),
                          IconButton(
                            onPressed: _sendTextMessage,
                            icon: Icon(Icons.arrow_upward_rounded,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5)),
                            iconSize: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                  secondChild: const SizedBox.shrink(),
                  crossFadeState: _showTextInput
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  duration: const Duration(milliseconds: 200),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _hintTextForMode(AgentMode mode) {
    switch (mode) {
      case AgentMode.general:
        return 'Ask anything…';
      case AgentMode.translator:
        return 'Type to translate…';
      case AgentMode.tutor:
        return 'Ask about this problem…';
      case AgentMode.support:
        return 'Describe your issue…';
    }
  }

  Widget _controlButton({
    required IconData icon,
    VoidCallback? onPressed,
    String? semanticLabel,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: semanticLabel,
      button: onPressed != null,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: onPressed != null
              ? onSurface.withValues(alpha: 0.08)
              : onSurface.withValues(alpha: 0.04),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon,
              color: onPressed != null
                  ? onSurface
                  : onSurface.withValues(alpha: 0.4)),
          iconSize: 28,
        ),
      ),
    );
  }
}

// ── Input mode chip ──────────────────────────────────────────────────────────
class _InputModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _InputModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? Colors.white
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
