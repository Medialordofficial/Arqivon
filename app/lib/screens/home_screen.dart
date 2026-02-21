import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../models/agent_mode.dart';
import '../providers/auth_provider.dart';

/// Callback-based so MainNavigator can jump to the Live tab.
class HomeScreen extends ConsumerWidget {
  final VoidCallback? onGoLive;
  const HomeScreen({super.key, this.onGoLive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: ArqivonTheme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Hero app bar ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            backgroundColor: ArqivonTheme.primary,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.fadeTitle,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Gradient background
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF4338CA),
                          Color(0xFF5B5FEF),
                          Color(0xFF0EA5E9),
                        ],
                      ),
                    ),
                  ),
                  // Decorative circles
                  Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.07),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: -30,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.05),
                      ),
                    ),
                  ),
                  // Content
                  Positioned(
                    bottom: 28,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (user != null)
                          Text(
                            'Welcome back,',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.75),
                              letterSpacing: 0.3,
                            ),
                          ),
                        Text(
                          user != null
                              ? (user.displayName?.split(' ').first ?? 'there')
                              : 'Arqivon',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your real-time multimodal AI — see, hear, understand.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.8),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (user != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundImage: user.photoURL != null
                        ? NetworkImage(user.photoURL!)
                        : null,
                    backgroundColor: Colors.white24,
                    child: user.photoURL == null
                        ? Text(
                            (user.displayName?.isNotEmpty == true)
                                ? user.displayName![0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                ),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Start CTA ───────────────────────────────────────
                _StartLiveCard(onGoLive: onGoLive),

                const SizedBox(height: 28),

                // ── Features heading ─────────────────────────────────
                const Text(
                  'What Arqivon can do',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ArqivonTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Four intelligent modes — all running live.',
                  style: TextStyle(
                    fontSize: 13,
                    color: ArqivonTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),

                // ── 2-column mode cards ──────────────────────────────
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.88,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [
                    _ModeCard(
                      mode: AgentMode.general,
                      color: ArqivonTheme.modeGeneral,
                      icon: Icons.auto_awesome_rounded,
                      description:
                          'Ask anything — point your camera, speak your question, get instant answers.',
                    ),
                    _ModeCard(
                      mode: AgentMode.translator,
                      color: ArqivonTheme.modeTranslator,
                      icon: Icons.translate_rounded,
                      description:
                          'Live bilingual captions translated in real time as you speak.',
                    ),
                    _ModeCard(
                      mode: AgentMode.tutor,
                      color: ArqivonTheme.modeTutor,
                      icon: Icons.school_rounded,
                      description:
                          'Point at a textbook, whiteboard, or diagram — get step-by-step guidance.',
                    ),
                    _ModeCard(
                      mode: AgentMode.support,
                      color: ArqivonTheme.modeSupport,
                      icon: Icons.headset_mic_rounded,
                      description:
                          'Voice-driven support scripts with topic tracking and smart suggestions.',
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ── How it works ─────────────────────────────────────
                const Text(
                  'How it works',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ArqivonTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),
                _HowItWorksStep(
                  step: 1,
                  title: 'Go Live',
                  body:
                      'Tap the Live tab and choose Audio‑only or Audio + Video.',
                  color: ArqivonTheme.primary,
                ),
                _HowItWorksStep(
                  step: 2,
                  title: 'Pick a mode',
                  body:
                      'Select General, Translator, Tutor, or Support at the top of the screen.',
                  color: ArqivonTheme.accent,
                ),
                _HowItWorksStep(
                  step: 3,
                  title: 'Talk & point',
                  body:
                      'Speak naturally. Arqivon listens and sees in real time — no uploads needed.',
                  color: ArqivonTheme.teal,
                ),
                _HowItWorksStep(
                  step: 4,
                  title: 'Review later',
                  body:
                      'Every session is saved to your Archive for later review.',
                  color: ArqivonTheme.modeSupport,
                  isLast: true,
                ),

                const SizedBox(height: 100), // nav bar clearance
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Start Live CTA card ──────────────────────────────────────────────────────
class _StartLiveCard extends StatelessWidget {
  final VoidCallback? onGoLive;
  const _StartLiveCard({this.onGoLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5B5FEF), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: ArqivonTheme.primary.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ready when you are',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Start a live session now — audio or video, your choice.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.8),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: onGoLive,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start Live'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: ArqivonTheme.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }
}

// ── Mode card ────────────────────────────────────────────────────────────────
class _ModeCard extends StatelessWidget {
  final AgentMode mode;
  final Color color;
  final IconData icon;
  final String description;

  const _ModeCard({
    required this.mode,
    required this.color,
    required this.icon,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              mode.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: ArqivonTheme.textSecondary,
                  height: 1.45,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── How it works step ────────────────────────────────────────────────────────
class _HowItWorksStep extends StatelessWidget {
  final int step;
  final String title;
  final String body;
  final Color color;
  final bool isLast;

  const _HowItWorksStep({
    required this.step,
    required this.title,
    required this.body,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$step',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            if (!isLast)
              Container(width: 2, height: 40, color: color.withOpacity(0.15)),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ArqivonTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: ArqivonTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
