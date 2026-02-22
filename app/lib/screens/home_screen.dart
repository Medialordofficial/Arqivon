// Light design — production grade.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      backgroundColor: Colors.white,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Compact sticky header ────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 0,
            toolbarHeight: 64 + topPad,
            elevation: 0,
            backgroundColor: Colors.white,
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
                      backgroundColor: const Color(0xFFF1F5F9),
                      child: user.photoURL == null
                          ? Text(
                              (user.displayName?.isNotEmpty == true)
                                  ? user.displayName![0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
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
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: Color(0xFF64748B), size: 22),
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
                            color: Color(0xFF64748B),
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
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_none_rounded,
                        color: Color(0xFF64748B), size: 24),
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
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Mode cards — 2×2 circular grid ─────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CircularModeCard(
                      icon: Icons.auto_awesome_rounded,
                      label: AgentMode.general.label,
                      accentColor: const Color(0xFF3B82F6),
                      onTap: onGoLive,
                    ),
                    _CircularModeCard(
                      icon: Icons.translate_rounded,
                      label: AgentMode.translator.label,
                      accentColor: const Color(0xFF0EA5E9),
                      onTap: onGoLive,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CircularModeCard(
                      icon: Icons.school_rounded,
                      label: AgentMode.tutor.label,
                      accentColor: const Color(0xFF818CF8),
                      onTap: onGoLive,
                    ),
                    _CircularModeCard(
                      icon: Icons.headset_mic_rounded,
                      label: AgentMode.support.label,
                      accentColor: const Color(0xFF22D3EE),
                      onTap: onGoLive,
                    ),
                  ],
                ),

                const SizedBox(height: 36),

                // ── How it works — animated circles + arrows ─────────
                const _HowItWorksSection(),

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

// ── Circular mode card ───────────────────────────────────────────────────────
class _CircularModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback? onTap;

  const _CircularModeCard({
    required this.icon,
    required this.label,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3),
                radius: 1.0,
                colors: [
                  accentColor.withValues(alpha: 0.12),
                  const Color(0xFFF1F5F9),
                ],
              ),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.25),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.10),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: accentColor, size: 40),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF0F172A).withValues(alpha: 0.85),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── How it works — animated section ──────────────────────────────────────────

class _StepData {
  final String title;
  final String description;
  final IconData icon;
  const _StepData(this.title, this.description, this.icon);
}

class _HowItWorksSection extends StatefulWidget {
  const _HowItWorksSection();

  @override
  State<_HowItWorksSection> createState() => _HowItWorksSectionState();
}

class _HowItWorksSectionState extends State<_HowItWorksSection> {
  int _selectedStep = 0;

  static const _steps = [
    _StepData(
      'Open Live',
      'Tap "Go Live" above — your AI session connects instantly in under 2 seconds.',
      Icons.play_circle_outline_rounded,
    ),
    _StepData(
      'Pick Mode',
      'Swipe the mode strip at the top to choose Assistant, Translator, Tutor, or Support.',
      Icons.tune_rounded,
    ),
    _StepData(
      'Speak / Show',
      'Talk naturally or point your camera at anything — Arqivon responds in real time.',
      Icons.record_voice_over_rounded,
    ),
    _StepData(
      'Review',
      'Every session is auto-saved to your Archive for replay, search, and reference.',
      Icons.history_rounded,
    ),
  ];

  static const _colors = [
    Color(0xFF3B82F6),
    Color(0xFF0EA5E9),
    Color(0xFF818CF8),
    Color(0xFF22D3EE),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How it works',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF60A5FA),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 24),

        // ── Numbered circles with animated arrows ────────────────
        SizedBox(
          height: 56,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const circleSize = 48.0;
              final spacing = (constraints.maxWidth - 4 * circleSize) / 3;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Arrows between circles
                  for (int i = 0; i < 3; i++)
                    Positioned(
                      left: (i + 1) * circleSize + i * spacing + 4,
                      top: circleSize / 2 - 1,
                      child: _AnimatedArrow(
                        width: spacing - 8,
                        color: _colors[i].withValues(alpha: 0.40),
                        delay: Duration(milliseconds: 400 + i * 200),
                      ),
                    ),
                  // Circles
                  for (int i = 0; i < 4; i++)
                    Positioned(
                      left: i * (circleSize + spacing),
                      top: 0,
                      child: _StepCircle(
                        number: i + 1,
                        color: _colors[i],
                        isSelected: _selectedStep == i,
                        onTap: () => setState(() => _selectedStep = i),
                        delay: Duration(milliseconds: i * 150),
                      ),
                    ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 20),

        // ── Expanded description card w/ animated swap ───────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          ),
          child: _StepDescriptionCard(
            key: ValueKey(_selectedStep),
            step: _steps[_selectedStep],
            color: _colors[_selectedStep],
          ),
        ),
      ],
    );
  }
}

// ── Step circle with entry animation ─────────────────────────────────────────
class _StepCircle extends StatelessWidget {
  final int number;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final Duration delay;

  const _StepCircle({
    required this.number,
    required this.color,
    required this.isSelected,
    required this.onTap,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? color : color.withValues(alpha: 0.10),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.30),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Text(
            '$number',
            style: TextStyle(
              color: isSelected ? Colors.white : color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    )
        .animate()
        .scale(
          begin: const Offset(0, 0),
          end: const Offset(1, 1),
          delay: delay,
          duration: 500.ms,
          curve: Curves.elasticOut,
        )
        .fadeIn(delay: delay, duration: 300.ms);
  }
}

// ── Animated dashed arrow ────────────────────────────────────────────────────
class _AnimatedArrow extends StatelessWidget {
  final double width;
  final Color color;
  final Duration delay;

  const _AnimatedArrow({
    required this.width,
    required this.color,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 2,
      child: CustomPaint(
        size: Size(width, 2),
        painter: _ArrowPainter(color: color),
      ),
    )
        .animate()
        .scaleX(
          begin: 0,
          end: 1,
          alignment: Alignment.centerLeft,
          delay: delay,
          duration: 500.ms,
          curve: Curves.easeOutCubic,
        )
        .fadeIn(delay: delay, duration: 300.ms);
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Dashed line
    const dashW = 6.0;
    const gap = 4.0;
    double x = 0;
    while (x < size.width - 8) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(min(x + dashW, size.width - 8), size.height / 2),
        paint,
      );
      x += dashW + gap;
    }

    // Arrow head
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width, size.height / 2)
      ..lineTo(size.width - 7, size.height / 2 - 4)
      ..lineTo(size.width - 7, size.height / 2 + 4)
      ..close();
    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Step description card ────────────────────────────────────────────────────
class _StepDescriptionCard extends StatelessWidget {
  final _StepData step;
  final Color color;

  const _StepDescriptionCard({
    super.key,
    required this.step,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border:
                  Border.all(color: color.withValues(alpha: 0.30), width: 1.5),
            ),
            child: Icon(step.icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step.description,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
