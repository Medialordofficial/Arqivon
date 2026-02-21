import 'dart:math';

import 'package:flutter/material.dart';

/// ChatGPT-style audio wave visualizer.
///
/// Shows a breathing orb when idle, and smooth multi-layer sine wave bars
/// when actively listening or responding — seamless, fluid, production quality.
class LiveWave extends StatefulWidget {
  const LiveWave({
    super.key,
    required this.isListening,
    required this.isResponding,
    this.color,
    this.size = 220,
  });

  /// True while the user's microphone is open.
  final bool isListening;

  /// True while the AI is playing back audio.
  final bool isResponding;

  final Color? color;

  /// Diameter of the orb / wave area.
  final double size;

  @override
  State<LiveWave> createState() => _LiveWaveState();
}

class _LiveWaveState extends State<LiveWave> with TickerProviderStateMixin {
  // Breathing (idle pulse)
  late final AnimationController _breathCtrl;
  late final Animation<double> _breathAnim;

  // Wave scroll (continuous left-to-right wave phase)
  late final AnimationController _waveCtrl;

  // Fade between idle orb and active bars
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();

    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _breathAnim = CurvedAnimation(
      parent: _breathCtrl,
      curve: Curves.easeInOutSine,
    );

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _syncFade();
  }

  @override
  void didUpdateWidget(LiveWave old) {
    super.didUpdateWidget(old);
    if (old.isListening != widget.isListening ||
        old.isResponding != widget.isResponding) {
      _syncFade();
    }
  }

  void _syncFade() {
    final active = widget.isListening || widget.isResponding;
    if (active) {
      _fadeCtrl.forward();
    } else {
      _fadeCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    _waveCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.color ?? const Color(0xFF5B5FEF);
    final isActive = widget.isListening || widget.isResponding;

    return AnimatedBuilder(
      animation: Listenable.merge([_breathAnim, _waveCtrl, _fadeCtrl]),
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Outer glow ring 3 ─────────────────────────────────
              _GlowRing(
                diameter: widget.size *
                    (0.88 + 0.06 * _breathAnim.value) *
                    (1 + 0.08 * _fadeCtrl.value),
                color: primary,
                opacity: 0.06 + 0.04 * _breathAnim.value,
              ),
              // ── Outer glow ring 2 ────────────────────────────────
              _GlowRing(
                diameter: widget.size *
                    (0.70 + 0.05 * _breathAnim.value) *
                    (1 + 0.06 * _fadeCtrl.value),
                color: primary,
                opacity: 0.1 + 0.05 * _breathAnim.value,
              ),
              // ── Inner glow ring ───────────────────────────────────
              _GlowRing(
                diameter: widget.size *
                    (0.52 + 0.04 * _breathAnim.value) *
                    (1 + 0.04 * _fadeCtrl.value),
                color: primary,
                opacity: 0.18 + 0.08 * _breathAnim.value,
              ),

              // ── Wave bars (active) ────────────────────────────────
              Opacity(
                opacity: _fadeCtrl.value.clamp(0.0, 1.0),
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _WaveBarPainter(
                    phase: _waveCtrl.value * 2 * pi,
                    breathValue: _breathAnim.value,
                    color: primary,
                    isResponding: widget.isResponding,
                  ),
                ),
              ),

              // ── Core orb ─────────────────────────────────────────
              Container(
                width: widget.size * (0.32 + 0.04 * _breathAnim.value),
                height: widget.size * (0.32 + 0.04 * _breathAnim.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      isActive
                          ? Color.lerp(primary, Colors.white, 0.3)!
                          : primary.withValues(alpha: 0.9),
                      primary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(
                          alpha: 0.5 + 0.2 * _breathAnim.value),
                      blurRadius:
                          24 + 16 * _breathAnim.value + 12 * _fadeCtrl.value,
                      spreadRadius: 2 + 4 * _fadeCtrl.value,
                    ),
                  ],
                ),
                child: Icon(
                  isActive
                      ? (widget.isResponding
                          ? Icons.volume_up_rounded
                          : Icons.mic_rounded)
                      : Icons.mic_none_rounded,
                  color: Colors.white,
                  size: widget.size * 0.14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Glow ring ─────────────────────────────────────────────────────────────────
class _GlowRing extends StatelessWidget {
  const _GlowRing({
    required this.diameter,
    required this.color,
    required this.opacity,
  });

  final double diameter;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: (opacity * 0.9).clamp(0, 1)),
          width: 1.5,
        ),
        color: color.withValues(alpha: (opacity * 0.35).clamp(0, 1)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: (opacity * 0.5).clamp(0, 1)),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

// ── Sine-wave bar painter ──────────────────────────────────────────────────────
class _WaveBarPainter extends CustomPainter {
  _WaveBarPainter({
    required this.phase,
    required this.breathValue,
    required this.color,
    required this.isResponding,
  });

  final double phase;
  final double breathValue;
  final Color color;
  final bool isResponding;

  static const int _barCount = 40;
  static final Random _rng = Random(7);
  // Pre-generate per-bar noise offsets so they're consistent
  static final List<double> _noise =
      List.generate(_barCount, (i) => _rng.nextDouble());

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = size.width * 0.48;
    final barW = (2 * pi * maxR * 0.55) / _barCount;

    for (int i = 0; i < _barCount; i++) {
      final angle = (2 * pi * i / _barCount) - pi / 2;

      // Wave amplitude: sine wave with phase scroll + per-bar noise
      final waveVal = 0.5 + 0.5 * sin(phase * 1.3 + i * (2 * pi / _barCount));
      final noised = 0.4 + 0.6 * (waveVal * (0.6 + 0.4 * _noise[i]));
      final amplitude = noised *
          (isResponding ? 0.88 : 0.65) *
          (0.7 + 0.3 * breathValue) *
          maxR *
          0.50;

      final barLen = amplitude.clamp(3.0, maxR * 0.52);
      final innerR = maxR * 0.38;

      final startX = cx + innerR * cos(angle);
      final startY = cy + innerR * sin(angle);
      final endX = cx + (innerR + barLen) * cos(angle);
      final endY = cy + (innerR + barLen) * sin(angle);

      final opacity = (0.55 + 0.45 * noised).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..strokeWidth = barW * 0.58
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveBarPainter old) =>
      old.phase != phase || old.breathValue != breathValue;
}
