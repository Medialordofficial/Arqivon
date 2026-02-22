// Dark Indigo design — production grade.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../models/agent_mode.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  final VoidCallback? onGoLive;
  const HomeScreen({super.key, this.onGoLive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: ArqivonTheme.darkBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Compact sticky header ────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 0,
            toolbarHeight: 64 + topPad,
            elevation: 0,
            backgroundColor: ArqivonTheme.darkSurface,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            flexibleSpace: Padding(
              padding:
                  EdgeInsets.only(top: topPad, left: 20, right: 16, bottom: 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (user != null)
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: user.photoURL != null
                          ? NetworkImage(user.photoURL!)
                          : null,
                      backgroundColor: ArqivonTheme.darkCard,
                      child: user.photoURL == null
                          ? Text(
                              (user.displayName?.isNotEmpty == true)
                                  ? user.displayName![0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: ArqivonTheme.darkText,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    )
                  else
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: ArqivonTheme.darkCard,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: ArqivonTheme.darkSubtext, size: 22),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user != null ? 'Welcome back,' : 'Hello,',
                          style: const TextStyle(
                            fontSize: 12,
                            color: ArqivonTheme.darkSubtext,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          user != null
                              ? (user.displayName?.split(' ').first ?? 'there')
                              : 'Arqivon',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: ArqivonTheme.darkText,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_none_rounded,
                        color: ArqivonTheme.darkSubtext, size: 24),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Hero Go Live button ──────────────────────────────
                _GoLiveButton(onTap: onGoLive),

                const SizedBox(height: 32),

                // ── Section heading ──────────────────────────────────
                const Text(
                  'Choose your mode',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF60A5FA), // light vibrant blue
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'All four run live — audio and video, no uploads.',
                  style: TextStyle(
                    fontSize: 13,
                    color: ArqivonTheme.darkSubtext,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Mode cards — full-width vertical list ─────────────
                _ModeCard(
                  icon: Icons.auto_awesome_rounded,
                  label: AgentMode.general.label,
                  description:
                      'Ask anything. Point your camera, speak your question, get instant answers.',
                  accentColor: const Color(0xFF3B82F6), // blue-500
                  onTap: onGoLive,
                ),
                const SizedBox(height: 10),
                _ModeCard(
                  icon: Icons.translate_rounded,
                  label: AgentMode.translator.label,
                  description:
                      'Live bilingual captions — translated in real time as you speak.',
                  accentColor: const Color(0xFF0EA5E9), // sky-500
                  onTap: onGoLive,
                ),
                const SizedBox(height: 10),
                _ModeCard(
                  icon: Icons.school_rounded,
                  label: AgentMode.tutor.label,
                  description:
                      'Point at a textbook or whiteboard — get step-by-step guided explanations.',
                  accentColor: const Color(0xFF818CF8), // indigo-400
                  onTap: onGoLive,
                ),
                const SizedBox(height: 10),
                _ModeCard(
                  icon: Icons.headset_mic_rounded,
                  label: AgentMode.support.label,
                  description:
                      'Voice-driven support flows with topic tracking and smart suggestions.',
                  accentColor: const Color(0xFF22D3EE), // cyan-400
                  onTap: onGoLive,
                ),

                const SizedBox(height: 32),

                // ── How it works ─────────────────────────────────────
                const Text(
                  'How it works',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ArqivonTheme.darkText,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 16),
                const _Step(
                  number: '1',
                  title: 'Open the Live tab',
                  body:
                      'Tap "Live" at the bottom — your session connects automatically.',
                  color: ArqivonTheme.primary,
                ),
                const _Step(
                  number: '2',
                  title: 'Pick a mode',
                  body:
                      'Select General, Translator, Tutor, or Support from the chips at the top.',
                  color: ArqivonTheme.accent,
                ),
                const _Step(
                  number: '3',
                  title: 'Speak or show',
                  body:
                      'Talk naturally or point your camera — Arqivon responds in real time.',
                  color: ArqivonTheme.teal,
                ),
                const _Step(
                  number: '4',
                  title: 'Review later',
                  body:
                      'Every session is saved to your Archive for replay and reference.',
                  color: ArqivonTheme.modeSupport,
                  isLast: true,
                ),

                const SizedBox(height: 120),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Go Live hero button ───────────────────────────────────────────────────────
class _GoLiveButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _GoLiveButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF0055FF), // deep electric blue
              Color(0xFF0099FF), // vivid sky blue
              Color(0xFF00C6FF), // bright cyan-blue
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0070FF).withValues(alpha: 0.50),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Go Live',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  'Tap to start your session',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}

// ── Mode card ────────────────────────────────────────────────────────────────
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color accentColor;
  final VoidCallback? onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: ArqivonTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.30),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // ── Circular icon button ─────────────────────────────
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      accentColor,
                      accentColor.withValues(alpha: 0.70),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.40),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: ArqivonTheme.darkSubtext,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: accentColor.withValues(alpha: 0.60),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── How it works step ────────────────────────────────────────────────────────
class _Step extends StatelessWidget {
  final String number;
  final String title;
  final String body;
  final Color color;
  final bool isLast;

  const _Step({
    required this.number,
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border:
                    Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            if (!isLast)
              Container(
                  width: 2, height: 44, color: color.withValues(alpha: 0.18)),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ArqivonTheme.darkText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: ArqivonTheme.darkSubtext,
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
