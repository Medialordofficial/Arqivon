import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Glowing volumetric orb — ChatGPT-inspired white × light blue.
///
/// Idle: soft breathing sphere with white→light-blue radial gradient.
/// Listening: orb expands, outer glow intensifies, ripple rings emanate.
/// Responding: orb pulses with warmer white shift.
class LiveWave extends StatefulWidget {
  const LiveWave({
    super.key,
    required this.isListening,
    required this.isResponding,
    this.amplitude = 0.0,
    this.color,
    this.size = 260,
  });

  final bool isListening;
  final bool isResponding;

  /// Mic RMS amplitude (0.0–1.0) driving audio-reactive pulsing.
  final double amplitude;

  /// Accent tint (blended subtly into the orb's palette).
  final Color? color;

  /// Bounding square for the orb.
  final double size;

  @override
  State<LiveWave> createState() => _LiveWaveState();
}

class _LiveWaveState extends State<LiveWave> with TickerProviderStateMixin {
  // Slow breathing — always running
  late final AnimationController _breathCtrl;
  late final Animation<double> _breathAnim;

  // Ripple rings — only when active
  late final AnimationController _ripple1;
  late final AnimationController _ripple2;
  late final AnimationController _ripple3;

  // Active state crossfade
  late final AnimationController _activeCtrl;

  @override
  void initState() {
    super.initState();

    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _breathAnim = CurvedAnimation(
      parent: _breathCtrl,
      curve: Curves.easeInOutSine,
    );

    // Staggered ripple rings
    _ripple1 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _ripple2 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _ripple3 = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();

    // Stagger start times
    Future.delayed(const Duration(milliseconds: 650),
        () => mounted ? _ripple2.forward() : null);
    Future.delayed(const Duration(milliseconds: 1300),
        () => mounted ? _ripple3.forward() : null);

    _activeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _syncActive();
  }

  @override
  void didUpdateWidget(LiveWave old) {
    super.didUpdateWidget(old);
    if (old.isListening != widget.isListening ||
        old.isResponding != widget.isResponding) {
      _syncActive();
    }
  }

  void _syncActive() {
    if (widget.isListening || widget.isResponding) {
      _activeCtrl.forward();
    } else {
      _activeCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _breathCtrl.dispose();
    _ripple1.dispose();
    _ripple2.dispose();
    _ripple3.dispose();
    _activeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [_breathAnim, _ripple1, _ripple2, _ripple3, _activeCtrl]),
      builder: (context, _) {
        final breathe = _breathAnim.value;
        final active = _activeCtrl.value;
        final isResponding = widget.isResponding;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _OrbPainter(
              breathe: breathe,
              active: active,
              amplitude: widget.amplitude,
              ripple1: _ripple1.value,
              ripple2: _ripple2.value,
              ripple3: _ripple3.value,
              isResponding: isResponding,
              accentColor: widget.color,
            ),
          ),
        );
      },
    );
  }
}

// ── Orb painter ───────────────────────────────────────────────────────────────
class _OrbPainter extends CustomPainter {
  const _OrbPainter({
    required this.breathe,
    required this.active,
    required this.amplitude,
    required this.ripple1,
    required this.ripple2,
    required this.ripple3,
    required this.isResponding,
    this.accentColor,
  });

  final double breathe;
  final double active;
  final double amplitude;
  final double ripple1;
  final double ripple2;
  final double ripple3;
  final bool isResponding;
  final Color? accentColor;

  // Orb color palette — ChatGPT-inspired white × light blue
  static const _whiteHi = Color(0xFFFFFFFF);
  static const _lightBlue = Color(0xFFB0D4F1);
  static const _skyBlue = Color(0xFF8ABFE0);
  static const _softBlue = Color(0xFF7FB5E0);
  static const _paleBlue = Color(0xFFD0E8F8);
  static const _edgeBlue = Color(0xFFE8F4FD);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = size.width * (0.375 + 0.025 * breathe);
    // Audio-reactive expansion: orb grows up to 10% with voice amplitude.
    final orbR = baseR * (1.0 + 0.04 * active + 0.10 * amplitude * active);

    // ── 1. Ambient outer glow — largest, very soft ────────────────────
    _paintGlow(
        canvas,
        cx,
        cy,
        orbR * 1.95,
        _softBlue.withValues(alpha: 0.08 + 0.06 * active + 0.06 * amplitude),
        _softBlue.withValues(alpha: 0.0),
        blurSigma: orbR * 0.6);

    _paintGlow(
        canvas,
        cx,
        cy,
        orbR * 1.58,
        _lightBlue.withValues(alpha: 0.14 + 0.10 * active + 0.08 * amplitude),
        _lightBlue.withValues(alpha: 0.0),
        blurSigma: orbR * 0.4);

    // ── 2. Ripple rings (visible when active) ─────────────────────────
    _paintRipple(canvas, cx, cy, orbR, ripple1, active);
    _paintRipple(canvas, cx, cy, orbR, ripple2, active);
    _paintRipple(canvas, cx, cy, orbR, ripple3, active);

    // ── 3. Core sphere — layered radial gradients ─────────────────────
    final sphereGrad = ui.Gradient.radial(
      Offset(cx - orbR * 0.30, cy - orbR * 0.28), // off-center focal highlight
      orbR,
      isResponding
          ? [
              _whiteHi, // bright white highlight
              const Color(0xFFE0EFFA), // very light blue
              _lightBlue, // mid light blue
              _skyBlue, // deeper sky blue
              _paleBlue, // pale edge
            ]
          : [
              _whiteHi, // bright highlight (top-left)
              const Color(0xFFF0F8FF), // alice blue
              _paleBlue, // pale blue mid
              _lightBlue, // light blue body
              _skyBlue, // sky blue edge
              _edgeBlue, // edge fade
            ],
      isResponding
          ? [0.0, 0.22, 0.50, 0.80, 1.0]
          : [0.0, 0.18, 0.40, 0.65, 0.85, 1.0],
    );

    final spherePaint = Paint()
      ..shader = sphereGrad
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0);

    canvas.drawCircle(Offset(cx, cy), orbR, spherePaint);

    // ── 4. Specular highlight — small bright ellipse top-left ─────────
    final hlPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx - orbR * 0.28, cy - orbR * 0.28),
        orbR * 0.38,
        [
          Colors.white.withValues(alpha: 0.85),
          Colors.white.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(
        Offset(cx - orbR * 0.25, cy - orbR * 0.26), orbR * 0.38, hlPaint);

    // ── 5. Edge rim glow ──────────────────────────────────────────────
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = orbR * 0.04
      ..shader = ui.Gradient.sweep(
        Offset(cx, cy),
        [
          _lightBlue.withValues(alpha: 0.0),
          _lightBlue.withValues(alpha: 0.5),
          _skyBlue.withValues(alpha: 0.4),
          _paleBlue.withValues(alpha: 0.3),
          _lightBlue.withValues(alpha: 0.0),
        ],
        [0.0, 0.18, 0.5, 0.75, 1.0],
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.04);
    canvas.drawCircle(Offset(cx, cy), orbR - orbR * 0.02, rimPaint);

    // ── 6. Inner micro glow center ────────────────────────────────────
    final corePaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy),
        orbR * 0.45,
        [
          _whiteHi.withValues(alpha: 0.35),
          _whiteHi.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(Offset(cx, cy), orbR * 0.45, corePaint);
  }

  void _paintGlow(
    Canvas canvas,
    double cx,
    double cy,
    double r,
    Color inner,
    Color outer, {
    required double blurSigma,
  }) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy),
        r,
        [inner, outer],
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
    canvas.drawCircle(Offset(cx, cy), r, paint);
  }

  void _paintRipple(Canvas canvas, double cx, double cy, double orbR,
      double rippleT, double activeAmt) {
    if (activeAmt < 0.01) return;
    // Ripple expands from 1x to ~1.9x orb radius and fades out
    final curved = Curves.easeOut.transform(rippleT);
    final r = orbR * (1.0 + curved * 0.9);
    final alpha = (1.0 - curved) * 0.35 * activeAmt;
    if (alpha < 0.01) return;
    final paint = Paint()
      ..color = _softBlue.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(cx, cy), r, paint);
  }

  @override
  bool shouldRepaint(_OrbPainter o) =>
      o.breathe != breathe ||
      o.active != active ||
      o.amplitude != amplitude ||
      o.ripple1 != ripple1 ||
      o.ripple2 != ripple2 ||
      o.ripple3 != ripple3;
}
