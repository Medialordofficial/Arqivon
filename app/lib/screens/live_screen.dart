import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../config/logger.dart';
import '../main.dart';
import '../models/agent_mode.dart';
import '../models/chat_message.dart';
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
  bool _isCapturingFrame = false;
  final TextEditingController _textController = TextEditingController();
  bool _showTextInput = false;
  _LiveInputMode _inputMode = _LiveInputMode.audioOnly;
  int _consecutiveFrameFailures = 0;
  static const _maxConsecutiveFrameFailures = 10;

  final ScrollController _chatScrollController = ScrollController();

  // ── Adaptive video frame rate ─────────────────────────────────────
  Duration _currentFrameInterval = AppConstants.frameCaptureInterval;
  static const Duration _minFrameInterval =
      Duration(milliseconds: 250); // ~4 fps
  static const Duration _maxFrameInterval =
      Duration(milliseconds: 800); // ~1.25 fps
  int _fastFrameCount = 0;
  int _slowFrameCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.tabNotifier.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(liveSessionProvider.notifier).connectOnly();
      }
    });
  }

  void _onTabChanged() {
    if (widget.tabNotifier.index != 1) {
      // Leaving Live tab — stop the session.
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
        ResolutionPreset.low,
        enableAudio: false,
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
    _currentFrameInterval = AppConstants.frameCaptureInterval;
    _fastFrameCount = 0;
    _slowFrameCount = 0;
    _scheduleNextFrame();
  }

  void _scheduleNextFrame() {
    _frameTimer?.cancel();
    _frameTimer = Timer(_currentFrameInterval, () async {
      await _captureAndSendFrame();
      if (_frameTimer != null) _scheduleNextFrame();
    });
  }

  void _stopFrameCapture() {
    _frameTimer?.cancel();
    _frameTimer = null;
  }

  Future<void> _captureAndSendFrame() async {
    if (_isCapturingFrame) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    _isCapturingFrame = true;
    final sw = Stopwatch()..start();
    try {
      final file = await _cameraController!.takePicture();
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      ref.read(liveSessionProvider.notifier).sendVideoFrame(b64);
      _consecutiveFrameFailures = 0;

      final elapsedMs = sw.elapsedMilliseconds;
      if (elapsedMs > 400) {
        _slowFrameCount++;
        _fastFrameCount = 0;
        if (_slowFrameCount >= 3 && _currentFrameInterval < _maxFrameInterval) {
          _currentFrameInterval = Duration(
            milliseconds:
                (_currentFrameInterval.inMilliseconds * 1.5).toInt().clamp(
                      _minFrameInterval.inMilliseconds,
                      _maxFrameInterval.inMilliseconds,
                    ),
          );
          _slowFrameCount = 0;
        }
      } else if (elapsedMs < 200) {
        _fastFrameCount++;
        _slowFrameCount = 0;
        if (_fastFrameCount >= 5 && _currentFrameInterval > _minFrameInterval) {
          _currentFrameInterval = Duration(
            milliseconds:
                (_currentFrameInterval.inMilliseconds * 0.8).toInt().clamp(
                      _minFrameInterval.inMilliseconds,
                      _maxFrameInterval.inMilliseconds,
                    ),
          );
          _fastFrameCount = 0;
        }
      }
    } catch (e) {
      _consecutiveFrameFailures++;
      if (_consecutiveFrameFailures >= _maxConsecutiveFrameFailures) {
        _log.warning(
          'Camera capture failed $_consecutiveFrameFailures times, stopping: $e',
        );
        _stopFrameCapture();
      } else {
        _log.fine('Frame capture failed ($_consecutiveFrameFailures): $e');
      }
    } finally {
      _isCapturingFrame = false;
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
  }

  /// Capture a high-resolution photo and save it to the device.
  Future<void> _captureHighResPhoto(String description) async {
    // Clear the pending request so it doesn't re-trigger.
    ref.read(liveSessionProvider.notifier).clearPhotoCapture();

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _log.warning('Photo capture requested but camera not ready');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera not available for photo capture'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      _log.info('Capturing high-res photo: $description');
      // Pause frame capture briefly so takePicture doesn't conflict.
      _stopFrameCapture();

      final XFile file = await _cameraController!.takePicture();
      final bytes = await file.readAsBytes();

      // Save to app documents directory.
      final dir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${dir.path}/ArqivonPhotos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = description
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_')
          .toLowerCase();
      final filename = safeName.isEmpty
          ? 'photo_$timestamp.jpg'
          : '${safeName}_$timestamp.jpg';
      final savedFile = File('${photosDir.path}/$filename');
      await savedFile.writeAsBytes(bytes);

      _log.info('Photo saved: ${savedFile.path}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo captured: $description'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Resume frame capture if still in video mode.
      if (_inputMode == _LiveInputMode.audioVideo &&
          (ref.read(liveSessionProvider).valueOrNull?.isStreaming ?? false)) {
        _startFrameCapture();
      }
    } catch (e, st) {
      _log.severe('Photo capture failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo capture failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      // Resume frame capture even on failure.
      if (_inputMode == _LiveInputMode.audioVideo &&
          (ref.read(liveSessionProvider).valueOrNull?.isStreaming ?? false)) {
        _startFrameCapture();
      }
    }
  }

  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    widget.tabNotifier.removeListener(_onTabChanged);
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _cameraController?.dispose();
    _textController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(liveSessionProvider);
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // ── Listeners ──────────────────────────────────────────────────
    ref.listen<AsyncValue<LiveSessionState>>(liveSessionProvider, (prev, next) {
      if (next is AsyncError && prev is! AsyncError) {
        final errMsg = next.error?.toString() ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            behavior: SnackBarBehavior.floating,
            backgroundColor: theme.colorScheme.error,
            action: SnackBarAction(
              label: 'Retry',
              textColor: theme.colorScheme.onError,
              onPressed: () {
                ref.read(liveSessionProvider.notifier).connectOnly();
              },
            ),
          ),
        );
      }
    });

    ref.listen<AsyncValue<LiveSessionState>>(liveSessionProvider, (prev, next) {
      final oldMode = prev?.valueOrNull?.mode;
      final newMode = next.valueOrNull?.mode;
      if (oldMode != null && newMode != null && oldMode != newMode) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(newMode.icon, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Switched to ${newMode.label}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: newMode.color,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    });

    // Auto-scroll on new messages
    ref.listen<AsyncValue<LiveSessionState>>(liveSessionProvider, (prev, next) {
      final oldLen = prev?.valueOrNull?.chatMessages.length ?? 0;
      final newLen = next.valueOrNull?.chatMessages.length ?? 0;
      if (newLen > oldLen) _scrollToBottom();
    });

    // Photo capture requested by Gemini
    ref.listen<AsyncValue<LiveSessionState>>(liveSessionProvider, (prev, next) {
      final desc = next.valueOrNull?.pendingPhotoCapture;
      final prevDesc = prev?.valueOrNull?.pendingPhotoCapture;
      if (desc != null && desc != prevDesc) {
        _captureHighResPhoto(desc);
      }
    });

    final session = sessionAsync.valueOrNull;
    final isStreaming = session?.isStreaming ?? false;
    final isResponding = session?.isResponding ?? false;
    final isMuted = session?.isMuted ?? true;
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
    final chatMessages = session?.chatMessages ?? [];

    const orbSize = 180.0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ══════════════════════════════════════════════════════
              // TOP BAR: connection + mode badge
              // ══════════════════════════════════════════════════════
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    ConnectionIndicator(state: connectionState),
                    const Spacer(),
                    if (isStreaming)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
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
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // ══════════════════════════════════════════════════════
              // MODE SELECTOR STRIP
              // ══════════════════════════════════════════════════════
              ModeSelectorStrip(
                selectedMode: mode,
                isStreaming: isStreaming,
                onModeSelected: (m) {
                  ref.read(liveSessionProvider.notifier).setMode(m);
                },
              ),

              const SizedBox(height: 4),

              // ══════════════════════════════════════════════════════
              // MAIN CONTENT: chat + overlays + orb
              // ══════════════════════════════════════════════════════
              Expanded(
                child: Stack(
                  children: [
                    // ── Camera preview background (A/V mode) ─────────
                    if (_inputMode == _LiveInputMode.audioVideo &&
                        _cameraReady &&
                        _cameraController != null) ...[
                      Positioned.fill(
                        child:
                            ClipRRect(child: CameraPreview(_cameraController!)),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.40),
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.75),
                              ],
                              stops: const [0, 0.15, 0.6, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],

                    // ── Chat + bottom controls column ──────────────────
                    Column(
                      children: [
                        // ── Chat area ──────────────────────────────────
                        Expanded(
                          child: chatMessages.isEmpty && !isStreaming
                              ? _buildEmptyState(theme, mode)
                              : _buildChatList(
                                  theme,
                                  chatMessages,
                                  transcript,
                                  userTranscript,
                                  isResponding,
                                  isStreaming,
                                ),
                        ),

                        // ── Mode-specific overlays ────────────────────
                        if (mode == AgentMode.translator &&
                            currentTranslation != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: TranslationOverlayWidget(
                                overlay: currentTranslation),
                          ),

                        if (mode == AgentMode.support &&
                            currentSupportTopic != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SupportTopicTracker(
                              currentTopic: currentSupportTopic,
                              allTopics: supportTopics,
                            ),
                          ),

                        // ── Action / tutor / export cards ─────────────
                        if (currentAction != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SmartActionCard(
                              action: currentAction,
                              onDismiss: () => ref
                                  .read(liveSessionProvider.notifier)
                                  .dismissAction(),
                              onPrimaryAction: () async {
                                HapticFeedback.mediumImpact();
                                ref
                                    .read(liveSessionProvider.notifier)
                                    .dismissAction();
                                final result =
                                    await ActionHandlerService.execute(
                                  currentAction,
                                  context,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(result),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),

                        if (mode == AgentMode.tutor && currentTutorStep != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: TutorGuidanceCard(
                              step: currentTutorStep,
                              onDismiss: () => ref
                                  .read(liveSessionProvider.notifier)
                                  .dismissTutorStep(),
                              onRequestHint: () {
                                ref.read(liveSessionProvider.notifier).sendText(
                                    'Can you give me a hint for the current step?');
                              },
                            ),
                          ),

                        if (pendingExport != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ExportDocumentCard(
                              doc: pendingExport,
                              onDismiss: () => ref
                                  .read(liveSessionProvider.notifier)
                                  .dismissExport(),
                            ),
                          ),

                        // ══════════════════════════════════════════════
                        // BOTTOM: Orb with action ring + status + input
                        // ══════════════════════════════════════════════
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                theme.scaffoldBackgroundColor
                                    .withValues(alpha: 0.0),
                                theme.scaffoldBackgroundColor,
                              ],
                              stops: const [0.0, 0.3],
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.only(bottom: bottomPad + 4),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // ── Orb with action ring ────────────
                                _OrbWithControls(
                                  orbSize: orbSize,
                                  isStreaming: isStreaming,
                                  isResponding: isResponding,
                                  isMuted: isMuted,
                                  mode: mode,
                                  inputMode: _inputMode,
                                  amplitudeNotifier: ref
                                      .read(liveSessionProvider.notifier)
                                      .amplitudeNotifier,
                                  onMicTap: () {
                                    HapticFeedback.heavyImpact();
                                    _toggleSession();
                                  },
                                  onMuteTap: () {
                                    HapticFeedback.mediumImpact();
                                    ref
                                        .read(liveSessionProvider.notifier)
                                        .toggleMute();
                                  },
                                  onVideoTap: () {
                                    HapticFeedback.lightImpact();
                                    setState(() {
                                      _inputMode =
                                          _inputMode == _LiveInputMode.audioOnly
                                              ? _LiveInputMode.audioVideo
                                              : _LiveInputMode.audioOnly;
                                    });
                                    if (_inputMode ==
                                            _LiveInputMode.audioVideo &&
                                        !_cameraReady) {
                                      _initCamera();
                                    }
                                    if (_inputMode ==
                                            _LiveInputMode.audioOnly &&
                                        isStreaming) {
                                      _stopFrameCapture();
                                    } else if (_inputMode ==
                                            _LiveInputMode.audioVideo &&
                                        isStreaming) {
                                      _startFrameCapture();
                                    }
                                  },
                                  onKeyboardTap: () {
                                    HapticFeedback.lightImpact();
                                    setState(
                                        () => _showTextInput = !_showTextInput);
                                  },
                                ),

                                // ── Status text ─────────────────────
                                _StatusText(
                                  isStreaming: isStreaming,
                                  isResponding: isResponding,
                                  isMuted: isMuted,
                                  connectionState: connectionState,
                                  mode: mode,
                                ),

                                // ── Text input ──────────────────────
                                AnimatedCrossFade(
                                  firstChild: Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(20, 6, 20, 4),
                                    child: _buildTextInput(theme, mode),
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
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // ── Empty state ─────────────────────────────────────────────────────
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState(ThemeData theme, AgentMode mode) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode.icon,
              size: 48,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _emptyStateTitle(mode),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _emptyStateSubtitle(mode),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _emptyStateTitle(AgentMode mode) {
    switch (mode) {
      case AgentMode.general:
        return 'Ready to assist';
      case AgentMode.translator:
        return 'Ready to translate';
      case AgentMode.tutor:
        return 'Ready to teach';
      case AgentMode.support:
        return 'How can I help?';
    }
  }

  String _emptyStateSubtitle(AgentMode mode) {
    switch (mode) {
      case AgentMode.general:
        return 'Tap the mic to start a conversation\nor type a message below';
      case AgentMode.translator:
        return 'Speak in any language and\nI\'ll translate in real-time';
      case AgentMode.tutor:
        return 'Ask a question or show me\na problem with your camera';
      case AgentMode.support:
        return 'Describe your issue and\nI\'ll help resolve it';
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // ── Chat list ───────────────────────────────────────────────────────
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildChatList(
    ThemeData theme,
    List<ChatMessage> messages,
    String? liveTranscript,
    String? liveUserTranscript,
    bool isResponding,
    bool isStreaming,
  ) {
    final hasLiveUser =
        liveUserTranscript != null && liveUserTranscript.isNotEmpty;
    final hasLiveAI = liveTranscript != null && liveTranscript.isNotEmpty;

    final itemCount =
        messages.length + (hasLiveUser ? 1 : 0) + (hasLiveAI ? 1 : 0);

    if (itemCount == 0) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      controller: _chatScrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < messages.length) {
          final msg = messages[index];
          if (msg.isSystem) {
            return _SystemBubble(text: msg.text, theme: theme);
          }
          return _ChatBubble(
            text: msg.text,
            isUser: msg.isUser,
            theme: theme,
          );
        }
        final liveIndex = index - messages.length;
        if (liveIndex == 0 && hasLiveUser) {
          return _ChatBubble(
            text: liveUserTranscript,
            isUser: true,
            isLive: true,
            theme: theme,
          );
        }
        return _ChatBubble(
          text: liveTranscript ?? '',
          isUser: false,
          isLive: true,
          theme: theme,
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // ── Text input ──────────────────────────────────────────────────────
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildTextInput(ThemeData theme, AgentMode mode) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
          width: 1,
        ),
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
                color: theme.colorScheme.onSurface,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: _hintTextForMode(mode),
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.40),
                  fontSize: 15,
                ),
                border: InputBorder.none,
                isDense: true,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onSubmitted: (_) => _sendTextMessage(),
            ),
          ),
          IconButton(
            onPressed: _sendTextMessage,
            icon: Icon(
              Icons.arrow_upward_rounded,
              color: theme.colorScheme.primary,
            ),
            iconSize: 22,
          ),
        ],
      ),
    );
  }

  String _hintTextForMode(AgentMode mode) {
    switch (mode) {
      case AgentMode.general:
        return 'Ask anything\u2026';
      case AgentMode.translator:
        return 'Type to translate\u2026';
      case AgentMode.tutor:
        return 'Ask about this problem\u2026';
      case AgentMode.support:
        return 'Describe your issue\u2026';
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Status text ───────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _StatusText extends StatelessWidget {
  const _StatusText({
    required this.isStreaming,
    required this.isResponding,
    required this.isMuted,
    required this.connectionState,
    required this.mode,
  });

  final bool isStreaming;
  final bool isResponding;
  final bool isMuted;
  final WsConnectionState connectionState;
  final AgentMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String text;
    double opacity;
    FontWeight weight;

    if (isResponding) {
      text = 'Speaking\u2026';
      opacity = 0.8;
      weight = FontWeight.w500;
    } else if (isStreaming && isMuted) {
      text = 'Mic muted — tap to unmute';
      opacity = 0.6;
      weight = FontWeight.w400;
    } else if (isStreaming) {
      text = 'Listening\u2026';
      opacity = 0.6;
      weight = FontWeight.w400;
    } else if (connectionState == WsConnectionState.connecting) {
      text = 'Connecting\u2026';
      opacity = 0.5;
      weight = FontWeight.w400;
    } else if (connectionState == WsConnectionState.reconnecting) {
      text = 'Reconnecting\u2026';
      opacity = 0.5;
      weight = FontWeight.w400;
    } else {
      text = 'Tap the mic to start';
      opacity = 0.45;
      weight = FontWeight.w400;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(
          text,
          key: ValueKey(text),
          style: TextStyle(
            fontSize: 14,
            fontWeight: weight,
            color: theme.colorScheme.onSurface.withValues(alpha: opacity),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Orb with circular action ring ─────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _OrbWithControls extends StatelessWidget {
  const _OrbWithControls({
    required this.orbSize,
    required this.isStreaming,
    required this.isResponding,
    required this.isMuted,
    required this.mode,
    required this.inputMode,
    required this.amplitudeNotifier,
    required this.onMicTap,
    required this.onMuteTap,
    required this.onVideoTap,
    required this.onKeyboardTap,
  });

  final double orbSize;
  final bool isStreaming;
  final bool isResponding;
  final bool isMuted;
  final AgentMode mode;
  final _LiveInputMode inputMode;
  final ValueNotifier<double> amplitudeNotifier;
  final VoidCallback onMicTap;
  final VoidCallback onMuteTap;
  final VoidCallback onVideoTap;
  final VoidCallback onKeyboardTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ringRadius = orbSize / 2 + 16;

    return SizedBox(
      width: orbSize + 80,
      height: orbSize + 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── The orb (tappable) — starts/stops session ────────────
          GestureDetector(
            onTap: onMicTap,
            child: ValueListenableBuilder<double>(
              valueListenable: amplitudeNotifier,
              builder: (context, amplitude, _) => LiveWave(
                isListening: isStreaming && !isResponding && !isMuted,
                isResponding: isResponding,
                amplitude: amplitude,
                color: mode.color,
                size: orbSize,
              ),
            ),
          ),

          // ── Mic/Mute button (top — 270 deg) ────────────────────
          // When NOT streaming: tap to start session
          // When streaming: tap to toggle mute/unmute
          _buildRingButton(
            context: context,
            angle: -math.pi / 2,
            radius: ringRadius,
            icon: isStreaming
                ? (isMuted ? Icons.mic_off_rounded : Icons.mic_rounded)
                : Icons.mic_rounded,
            isActive: isStreaming && !isMuted,
            activeColor: isStreaming
                ? (isMuted ? Colors.orange : theme.colorScheme.primary)
                : theme.colorScheme.primary,
            onTap: isStreaming ? onMuteTap : onMicTap,
            label: isStreaming ? (isMuted ? 'Unmute' : 'Mute') : 'Mic',
          ),

          // ── Stop button (only visible when streaming) ───────────
          if (isStreaming)
            _buildRingButton(
              context: context,
              angle: math.pi / 2, // bottom — 90 deg
              radius: ringRadius,
              icon: Icons.stop_rounded,
              isActive: true,
              activeColor: Colors.red,
              onTap: onMicTap, // orb tap = start/stop
              label: 'Stop',
            ),

          // ── Video button (bottom-left — 210 deg) ────────────────
          _buildRingButton(
            context: context,
            angle: math.pi * 7 / 6,
            radius: ringRadius,
            icon: inputMode == _LiveInputMode.audioVideo
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            isActive: inputMode == _LiveInputMode.audioVideo,
            activeColor: const Color(0xFF6B9F5B),
            onTap: onVideoTap,
            label: 'Video',
          ),

          // ── Keyboard button (bottom-right — 330 deg) ────────────
          _buildRingButton(
            context: context,
            angle: -math.pi / 6,
            radius: ringRadius,
            icon: Icons.keyboard_rounded,
            isActive: false,
            activeColor: theme.colorScheme.primary,
            onTap: onKeyboardTap,
            label: 'Type',
          ),
        ],
      ),
    );
  }

  Widget _buildRingButton({
    required BuildContext context,
    required double angle,
    required double radius,
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    required String label,
  }) {
    final theme = Theme.of(context);
    final dx = math.cos(angle) * radius;
    final dy = math.sin(angle) * radius;

    final bgColor =
        isActive ? activeColor : theme.colorScheme.surfaceContainerHighest;
    final iconColor = isActive
        ? Colors.white
        : theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                ),
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? activeColor
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Chat bubble ───────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.text,
    required this.isUser,
    required this.theme,
    this.isLive = false,
  });

  final String text;
  final bool isUser;
  final bool isLive;
  final ThemeData theme;

  /// Whether the text contains markdown formatting worth rendering.
  static bool _hasMarkdown(String text) {
    return text.contains('```') ||
        text.contains('**') ||
        text.contains('##') ||
        text.contains('- ') ||
        text.contains('1. ') ||
        text.contains('`') ||
        text.contains('\$\$') ||
        text.contains('[') && text.contains('](');
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isUser
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = theme.colorScheme.onSurface;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final useMarkdown = !isUser && !isLive && _hasMarkdown(text);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isLive)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                isUser ? 'You' : 'Arqivon',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isUser
                      ? theme.colorScheme.primary.withValues(alpha: 0.7)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: useMarkdown
                      ? MarkdownBody(
                          data: text,
                          selectable: true,
                          shrinkWrap: true,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              height: 1.4,
                            ),
                            code: TextStyle(
                              color: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.08),
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                            codeblockDecoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            codeblockPadding: const EdgeInsets.all(12),
                            h1: TextStyle(
                              color: textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                            h2: TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            h3: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            listBullet: TextStyle(
                              color: textColor.withValues(alpha: 0.7),
                              fontSize: 15,
                            ),
                            strong: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                            em: TextStyle(
                              color: textColor,
                              fontStyle: FontStyle.italic,
                            ),
                            blockquoteDecoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.5),
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                          onTapLink: (text, href, title) {
                            if (href != null) {
                              final uri = Uri.tryParse(href);
                              if (uri != null) launchUrl(uri);
                            }
                          },
                        )
                      : Text(
                          text,
                          style: TextStyle(
                            color:
                                textColor.withValues(alpha: isLive ? 0.6 : 1.0),
                            fontSize: 15,
                            height: 1.4,
                            fontStyle:
                                isLive ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                ),
                if (isLive) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── System message bubble ─────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.error.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
