// Design — supports dark + light theme.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_mode.dart';
import '../providers/auth_provider.dart';
import '../providers/live_session_provider.dart';
import '../providers/settings_provider.dart';

class HomeScreen extends ConsumerWidget {
  final VoidCallback? onGoLive;
  const HomeScreen({super.key, this.onGoLive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final settings = ref.watch(settingsProvider);
    final defaultMode = settings.defaultMode;
    final topPad = MediaQuery.of(context).padding.top;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Compact sticky header ───────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 0,
            toolbarHeight: 64 + topPad,
            elevation: 0,
            backgroundColor: cs.surface,
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
                      backgroundColor: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFDBEAFE),
                      child: user.photoURL == null
                          ? Text(
                              (user.displayName?.isNotEmpty == true)
                                  ? user.displayName![0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: cs.onSurface,
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
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFDBEAFE),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person_rounded,
                          color: cs.onSurface.withValues(alpha: 0.5), size: 22),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user != null ? 'Welcome back,' : 'Hello,',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.5),
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          user != null
                              ? (user.displayName?.split(' ').first ?? 'there')
                              : 'Arqivon',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Clean right side — no dead buttons
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
                Text(
                  'Choose your mode',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'All four run live — audio and video, no uploads.',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.5),
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
                      accentColor: const Color(0xFF2563EB),
                      isDefault: defaultMode == AgentMode.general,
                      onTap: () {
                        ref
                            .read(liveSessionProvider.notifier)
                            .setMode(AgentMode.general);
                        onGoLive?.call();
                      },
                    ),
                    _CircularModeCard(
                      icon: Icons.translate_rounded,
                      label: AgentMode.translator.label,
                      accentColor: const Color(0xFF2563EB),
                      isDefault: defaultMode == AgentMode.translator,
                      onTap: () {
                        ref
                            .read(liveSessionProvider.notifier)
                            .setMode(AgentMode.translator);
                        onGoLive?.call();
                      },
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
                      accentColor: const Color(0xFF2563EB),
                      isDefault: defaultMode == AgentMode.tutor,
                      onTap: () {
                        ref
                            .read(liveSessionProvider.notifier)
                            .setMode(AgentMode.tutor);
                        onGoLive?.call();
                      },
                    ),
                    _CircularModeCard(
                      icon: Icons.headset_mic_rounded,
                      label: AgentMode.support.label,
                      accentColor: const Color(0xFF2563EB),
                      isDefault: defaultMode == AgentMode.support,
                      onTap: () {
                        ref
                            .read(liveSessionProvider.notifier)
                            .setMode(AgentMode.support);
                        onGoLive?.call();
                      },
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
    return Semantics(
      label: 'Go Live. Tap to start your session',
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap?.call();
        },
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF2563EB),
                Color(0xFF3B82F6),
                Color(0xFF6366F1),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.50),
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
                child: const Icon(Icons.mic_rounded,
                    color: Colors.white, size: 24),
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
      ),
    );
  }
}

// ── Circular mode card ───────────────────────────────────────────────────────
class _CircularModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final bool isDefault;
  final VoidCallback? onTap;

  const _CircularModeCard({
    required this.icon,
    required this.label,
    required this.accentColor,
    this.isDefault = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: '$label mode${isDefault ? ' (default)' : ''}',
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap?.call();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DefaultModeGlow(
              isDefault: isDefault,
              accentColor: accentColor,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, -0.3),
                    radius: 1.0,
                    colors: [
                      accentColor.withValues(alpha: isDefault ? 0.18 : 0.08),
                      isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFFFFFFF),
                    ],
                  ),
                  border: Border.all(
                    color:
                        accentColor.withValues(alpha: isDefault ? 0.55 : 0.18),
                    width: isDefault ? 2.5 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(
                          alpha: isDefault ? 0.18 : 0.06),
                      blurRadius: isDefault ? 28 : 20,
                      spreadRadius: isDefault ? 4 : 2,
                    ),
                  ],
                ),
                child: Icon(icon,
                    color:
                        accentColor.withValues(alpha: isDefault ? 0.95 : 0.75),
                    size: 38),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: isDefault ? 1.0 : 0.85),
                    fontSize: 14,
                    fontWeight: isDefault ? FontWeight.w800 : FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                if (isDefault) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: accentColor.withValues(alpha: 0.8),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Default mode pulsing glow wrapper ────────────────────────────────────────
class _DefaultModeGlow extends StatefulWidget {
  final bool isDefault;
  final Color accentColor;
  final Widget child;

  const _DefaultModeGlow({
    required this.isDefault,
    required this.accentColor,
    required this.child,
  });

  @override
  State<_DefaultModeGlow> createState() => _DefaultModeGlowState();
}

class _DefaultModeGlowState extends State<_DefaultModeGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.isDefault) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_DefaultModeGlow old) {
    super.didUpdateWidget(old);
    if (widget.isDefault && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.isDefault && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isDefault) return widget.child;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return CustomPaint(
          painter: _DefaultModePainter(
            color: widget.accentColor,
            time: _ctrl.value * 8.0,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _DefaultModePainter extends CustomPainter {
  final Color color;
  final double time;

  _DefaultModePainter({required this.color, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = size.width / 2;

    final breathe = sin(time * 1.6) * 0.5 + 0.5;
    final breathe2 = sin(time * 2.3 + 1.0) * 0.5 + 0.5;

    // ── 1. Deep radiating aura (3 layers) ──────────────────────
    for (int layer = 0; layer < 3; layer++) {
      final layerPhase = sin(time * 1.2 + layer * 0.8) * 0.5 + 0.5;
      final auraR = baseR + 18 + layer * 10 + 8 * layerPhase;
      canvas.drawCircle(
        Offset(cx, cy),
        auraR,
        Paint()
          ..color =
              color.withValues(alpha: (0.08 - layer * 0.02) + 0.06 * layerPhase)
          ..maskFilter = MaskFilter.blur(
              BlurStyle.normal, 18 + layer * 6 + 6 * layerPhase),
      );
    }

    // ── 2. Primary rotating gradient comet trail ───────────────
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(time * 0.8);
    canvas.drawCircle(
      Offset.zero,
      baseR + 6,
      Paint()
        ..shader = SweepGradient(
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.70),
            color.withValues(alpha: 0.55),
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.08, 0.15, 0.22, 0.4, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: baseR + 6))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 + 1.0 * breathe
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 2 * breathe),
    );
    canvas.restore();

    // ── 3. Secondary counter-rotating trail ────────────────────
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-time * 0.55);
    canvas.drawCircle(
      Offset.zero,
      baseR + 12,
      Paint()
        ..shader = SweepGradient(
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.30),
            color.withValues(alpha: 0.40),
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.12, 0.24, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: baseR + 12))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();

    // ── 4. Rotating arc segments (4 arcs, 2 orbits) ────────────
    for (int ring = 0; ring < 2; ring++) {
      canvas.save();
      canvas.translate(cx, cy);
      final dir = ring == 0 ? 1.0 : -1.0;
      canvas.rotate(time * (0.45 + ring * 0.2) * dir);
      final arcR = baseR + 8 + ring * 6;
      for (int i = 0; i < 4; i++) {
        final startAngle = (i / 4) * pi * 2;
        final sweepAngle = pi * (0.25 + 0.08 * sin(time * 2.0 + i * 1.5));
        final arcAlpha = 0.22 + 0.18 * sin(time * 2.5 + i * 1.3 + ring * 2.0);
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: arcR),
          startAngle,
          sweepAngle,
          false,
          Paint()
            ..color = Color.lerp(color, Colors.white, 0.2 + 0.1 * ring)!
                .withValues(alpha: arcAlpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 - ring * 0.5
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      }
      canvas.restore();
    }

    // ── 5. Orbiting constellation particles (24) ───────────────
    final rng = Random(73);
    for (int i = 0; i < 24; i++) {
      final orbitSpeed = 0.25 + rng.nextDouble() * 0.5;
      final orbitR = baseR + 2 + rng.nextDouble() * 22;
      final baseSize = 1.2 + rng.nextDouble() * 2.8;
      final phase = rng.nextDouble() * pi * 2;

      final angle = phase + time * orbitSpeed;
      final wobbleR = sin(time * 2.8 + i * 0.9) * 4;
      final wobbleT = cos(time * 1.7 + i * 1.3) * 2;

      final px = cx + cos(angle) * (orbitR + wobbleR);
      final py = cy + sin(angle) * (orbitR + wobbleT);

      final twinkle = sin(time * 4.0 + i * 2.3) * 0.5 + 0.5;
      final alpha = 0.20 + 0.65 * twinkle;
      final pSize = baseSize * (0.5 + 0.7 * twinkle);

      // Bright center + soft glow
      canvas.drawCircle(
        Offset(px, py),
        pSize,
        Paint()
          ..color = Color.lerp(color, Colors.white, 0.4 + 0.4 * twinkle)!
              .withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, pSize * 0.4),
      );
      // Bloom halo
      if (twinkle > 0.6) {
        canvas.drawCircle(
          Offset(px, py),
          pSize * 2.5,
          Paint()
            ..color = color.withValues(alpha: (twinkle - 0.6) * 0.25)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, pSize * 2),
        );
      }
    }

    // ── 6. Expanding pulse rings (3 staggered) ─────────────────
    for (int i = 0; i < 3; i++) {
      final phase = ((time * 0.7 + i * 1.0) % 3.5) / 3.5;
      final eased = Curves.easeOutCubic.transform(phase);
      final ringR = baseR + 2 + eased * 28;
      final fade = 1.0 - eased;
      if (fade < 0.03) continue;
      canvas.drawCircle(
        Offset(cx, cy),
        ringR,
        Paint()
          ..color = Color.lerp(color, Colors.white, 0.3)!
              .withValues(alpha: fade * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * fade + 0.5
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 5 * eased),
      );
    }

    // ── 7. Sparkle flashes (random bright flickers) ────────────
    final sparkRng = Random(17);
    for (int i = 0; i < 6; i++) {
      final sparkAngle =
          sparkRng.nextDouble() * pi * 2 + time * 0.3 * (i.isEven ? 1.0 : -1.0);
      final sparkR = baseR + 4 + sparkRng.nextDouble() * 16;
      final flash = pow(sin(time * 5.0 + i * 3.7) * 0.5 + 0.5, 3.0).toDouble();
      if (flash < 0.3) continue;

      final sx = cx + cos(sparkAngle) * sparkR;
      final sy = cy + sin(sparkAngle) * sparkR;

      // Cross-shaped sparkle
      final sparkLen = 3.0 + 5.0 * flash;
      final sparkPaint = Paint()
        ..color = Colors.white.withValues(alpha: flash * 0.8)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);

      canvas.drawLine(
          Offset(sx - sparkLen, sy), Offset(sx + sparkLen, sy), sparkPaint);
      canvas.drawLine(
          Offset(sx, sy - sparkLen), Offset(sx, sy + sparkLen), sparkPaint);
    }

    // ── 8. Inner edge glow with color gradient ─────────────────
    canvas.drawCircle(
      Offset(cx, cy),
      baseR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.0),
            Color.lerp(color, Colors.white, 0.2)!
                .withValues(alpha: 0.10 + 0.08 * breathe2),
          ],
          stops: const [0.0, 0.78, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: baseR)),
    );
  }

  @override
  bool shouldRepaint(_DefaultModePainter old) => true;
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
    Color(0xFF2563EB),
    Color(0xFF2563EB),
    Color(0xFF2563EB),
    Color(0xFF2563EB),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How it works',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: cs.primary,
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
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
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
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
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
