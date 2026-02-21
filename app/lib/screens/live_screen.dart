import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../models/agent_mode.dart';
import '../providers/live_session_provider.dart';
import '../services/websocket_service.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/glassmorphic_card.dart';
import '../widgets/mode_selector.dart';
import '../widgets/smart_action_card.dart';
import '../widgets/support_topic_tracker.dart';
import '../widgets/translation_overlay.dart';
import '../widgets/tutor_guidance_card.dart';

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  Timer? _frameTimer;
  bool _cameraReady = false;
  final TextEditingController _textController = TextEditingController();
  bool _showTextInput = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
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
      debugPrint('[Camera] Init error: $e');
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
      await notifier.startSession();
      _startFrameCapture();
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
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _cameraController?.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(liveSessionProvider);
    final session = sessionAsync.valueOrNull;
    final isStreaming = session?.isStreaming ?? false;
    final connectionState =
        session?.connectionState ?? WsConnectionState.disconnected;
    final currentAction = session?.currentAction;
    final transcript = session?.transcript;
    final mode = session?.mode ?? AgentMode.general;
    final currentTranslation = session?.currentTranslation;
    final currentTutorStep = session?.currentTutorStep;
    final currentSupportTopic = session?.currentSupportTopic;
    final supportTopics = session?.supportTopics ?? [];

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ─────────────────────────────────────────
          if (_cameraReady && _cameraController != null)
            ClipRRect(
              child: CameraPreview(_cameraController!),
            )
          else
            Container(
              color: const Color(0xFF0F0F1A),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt_outlined,
                        size: 64, color: Colors.white24),
                    SizedBox(height: 16),
                    Text('Initializing camera…',
                        style: TextStyle(color: Colors.white38)),
                  ],
                ),
              ),
            ),

          // ── Dark gradient overlay for readability ──────────────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.35),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.75),
                  ],
                  stops: const [0, 0.2, 0.55, 1.0],
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
                      color: Colors.red.withOpacity(0.8),
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

          // ── Transcript overlay ──────────────────────────────────────
          if (transcript != null && transcript.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 94,
              left: 20,
              right: 20,
              child: GlassmorphicCard(
                blur: 20,
                opacity: 0.15,
                padding: const EdgeInsets.all(12),
                child: Text(
                  transcript,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
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
                onPrimaryAction: () {
                  ref.read(liveSessionProvider.notifier).dismissAction();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('${currentAction.actionType} executed'),
                    behavior: SnackBarBehavior.floating,
                  ));
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

          // ── Audio visualizer ────────────────────────────────────────
          if (isStreaming)
            Positioned(
              bottom: 140,
              left: 40,
              right: 40,
              child: AudioVisualizer(
                isActive: isStreaming,
                color: mode.color,
                height: 40,
              ),
            ),

          // ── Text input toggle ───────────────────────────────────────
          if (_showTextInput)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: GlassmorphicCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: _hintTextForMode(mode),
                          hintStyle: const TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendTextMessage(),
                      ),
                    ),
                    IconButton(
                      onPressed: _sendTextMessage,
                      icon: Icon(Icons.send_rounded, color: mode.color),
                    ),
                  ],
                ),
              ),
            ),

          // ── Bottom controls ─────────────────────────────────────────
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Text input toggle
                _controlButton(
                  icon: Icons.keyboard_rounded,
                  onPressed: () =>
                      setState(() => _showTextInput = !_showTextInput),
                ),
                // Main record button
                GestureDetector(
                  onTap: _toggleSession,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isStreaming ? Colors.red : mode.color,
                      boxShadow: [
                        BoxShadow(
                          color: (isStreaming ? Colors.red : mode.color)
                              .withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      isStreaming ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Camera flip
                _controlButton(
                  icon: Icons.flip_camera_ios_rounded,
                  onPressed: () async {
                    final cameras = await availableCameras();
                    if (cameras.length < 2) return;
                    final current = _cameraController?.description;
                    final next = cameras.firstWhere(
                      (c) => c.lensDirection != current?.lensDirection,
                      orElse: () => cameras.first,
                    );
                    await _cameraController?.dispose();
                    _cameraController = CameraController(
                      next,
                      ResolutionPreset.medium,
                      enableAudio: false,
                    );
                    await _cameraController!.initialize();
                    if (mounted) setState(() {});
                  },
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
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.15),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        iconSize: 28,
      ),
    );
  }
}
