import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A dark, glossy, ChatGPT-style AI orb.
///
/// Minimalist and premium: smooth morphing blob, glass-like specular,
/// subtle colored rim light, gentle audio-reactive surface ripples.
/// No particles, no halos, no rings — pure elegance.
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
  final double amplitude;
  final Color? color;
  final double size;

  @override
  State<LiveWave> createState() => _LiveWaveState();
}

class _LiveWaveState extends State<LiveWave> with TickerProviderStateMixin {
  late final AnimationController _clock;
  late final AnimationController _activeCtrl;
  late final AnimationController _respondCtrl;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
    _activeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      value: 0,
    );
    _respondCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 0,
    );
    _syncState();
  }

  @override
  void didUpdateWidget(LiveWave old) {
    super.didUpdateWidget(old);
    if (old.isListening != widget.isListening ||
        old.isResponding != widget.isResponding) {
      _syncState();
    }
  }

  void _syncState() {
    final active = widget.isListening || widget.isResponding;
    if (active) {
      _activeCtrl.forward();
    } else {
      _activeCtrl.reverse();
    }
    if (widget.isResponding) {
      _respondCtrl.forward();
    } else {
      _respondCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _activeCtrl.dispose();
    _respondCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_clock, _activeCtrl, _respondCtrl]),
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _DarkOrbPainter(
              time: _clock.value * 120.0,
              active: _activeCtrl.value,
              responding: _respondCtrl.value,
              amplitude: widget.amplitude,
              modeColor: widget.color,
            ),
          ),
        );
      },
    );
  }
}

// ─── Accent colour from mode ───────────────────────────────────────────

Color _accentFromMode(Color? c) {
  if (c == null) return const Color(0xFF5E9FD1); // default blue
  final hue = HSLColor.fromColor(c).hue;
  if (hue >= 250 && hue < 310) return const Color(0xFF9B7AFF); // purple
  if (hue >= 80 && hue < 170) return const Color(0xFF3DDC97); // green
  if (hue >= 20 && hue < 55) return const Color(0xFFFF9F43); // orange
  if (hue >= 190 && hue < 250) return const Color(0xFF4A8EC9); // blue
  if (hue >= 330 || hue < 20) return const Color(0xFFFF6B6B); // red
  return const Color(0xFF5E9FD1);
}

// ─── The painter ───────────────────────────────────────────────────────

class _DarkOrbPainter extends CustomPainter {
  _DarkOrbPainter({
    required this.time,
    required this.active,
    required this.responding,
    required this.amplitude,
    this.modeColor,
  });

  final double time;
  final double active;
  final double responding;
  final double amplitude;
  final Color? modeColor;

  // ── Constants ──────────────
  static const _dark = Color(0xFF0A0A0F);
  static const _darkMid = Color(0xFF151520);
  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = size.width * 0.32;
    final amp = amplitude.clamp(0.0, 1.0);
    final accent = _accentFromMode(modeColor);

    // Orb radius: very subtle audio-reactive scaling.
    final orbR = baseR * (1.0 + 0.03 * active + 0.08 * amp * active);

    _drawAmbientGlow(canvas, cx, cy, orbR, accent);
    _drawShadow(canvas, cx, cy, orbR);
    _drawDarkSphere(canvas, cx, cy, orbR, accent, amp);
    _drawRimLight(canvas, cx, cy, orbR, accent, amp);
    _drawSpecularHighlight(canvas, cx, cy, orbR);
    _drawSubtleSurfaceRipple(canvas, cx, cy, orbR, accent, amp);
  }

  // ── 1. Ambient glow beneath the orb ──────────────────────────────

  void _drawAmbientGlow(
      Canvas canvas, double cx, double cy, double orbR, Color accent) {
    // Outer very soft glow — breathing.
    final breathe = math.sin(time * 0.4) * 0.5 + 0.5;
    final glowR = orbR * (1.6 + 0.08 * breathe);
    final glowAlpha = 0.04 + 0.06 * active + 0.04 * responding;
    canvas.drawCircle(
      Offset(cx, cy),
      glowR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          glowR,
          [
            accent.withValues(alpha: glowAlpha),
            accent.withValues(alpha: glowAlpha * 0.4),
            accent.withValues(alpha: 0),
          ],
          [0.0, 0.45, 1.0],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.5),
    );
  }

  // ── 2. Drop shadow ──────────────────────────────────────────────

  void _drawShadow(Canvas canvas, double cx, double cy, double orbR) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + orbR * 0.85),
        width: orbR * 1.3,
        height: orbR * 0.15,
      ),
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.35),
    );
  }

  // ── 3. Dark sphere body (morphing blob) ──────────────────────────

  void _drawDarkSphere(Canvas canvas, double cx, double cy, double orbR,
      Color accent, double amp) {
    final path = _morphedPath(cx, cy, orbR, amp);

    // Base dark fill.
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx - orbR * 0.15, cy - orbR * 0.15),
          orbR * 1.3,
          [_darkMid, _dark, const Color(0xFF050508)],
          [0.0, 0.55, 1.0],
        ),
    );

    // Subtle internal color tint from mode (barely visible).
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy + orbR * 0.25),
          orbR,
          [
            accent.withValues(alpha: 0.04 + 0.03 * responding),
            accent.withValues(alpha: 0.02 * active),
            accent.withValues(alpha: 0),
          ],
          [0.0, 0.4, 1.0],
        ),
    );
  }

  // ── 4. Rim light ─────────────────────────────────────────────────

  void _drawRimLight(Canvas canvas, double cx, double cy, double orbR,
      Color accent, double amp) {
    final path = _morphedPath(cx, cy, orbR, amp);

    // Rim: brighter at edges, dark at centre.
    final rimAlpha = 0.12 + 0.15 * active + 0.10 * responding;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          orbR,
          [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0),
            accent.withValues(alpha: rimAlpha),
          ],
          [0.0, 0.72, 1.0],
        ),
    );

    // Thin bright rim stroke.
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.sweep(
          Offset(cx, cy),
          [
            accent.withValues(alpha: 0.0),
            accent.withValues(alpha: 0.30 * active + 0.10),
            _white.withValues(alpha: 0.12 * active),
            accent.withValues(alpha: 0.25 * active + 0.08),
            accent.withValues(alpha: 0.0),
          ],
          [0.0, 0.25, 0.50, 0.75, 1.0],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * 0.02 + orbR * 0.008 * amp * active
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.012),
    );
  }

  // ── 5. Glass specular highlight ──────────────────────────────────

  void _drawSpecularHighlight(
      Canvas canvas, double cx, double cy, double orbR) {
    // Primary highlight — top-left.
    final hlx = cx - orbR * 0.24;
    final hly = cy - orbR * 0.28;
    final hlR = orbR * 0.42;
    canvas.drawCircle(
      Offset(hlx, hly),
      hlR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(hlx, hly),
          hlR,
          [
            _white.withValues(alpha: 0.55),
            _white.withValues(alpha: 0.18),
            _white.withValues(alpha: 0),
          ],
          [0.0, 0.30, 1.0],
        ),
    );

    // Secondary tiny highlight — bottom-right reflection.
    final h2x = cx + orbR * 0.20;
    final h2y = cy + orbR * 0.22;
    canvas.drawCircle(
      Offset(h2x, h2y),
      orbR * 0.08,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(h2x, h2y),
          orbR * 0.08,
          [
            _white.withValues(alpha: 0.12),
            _white.withValues(alpha: 0),
          ],
        ),
    );
  }

  // ── 6. Subtle surface ripple (audio-reactive) ────────────────────

  void _drawSubtleSurfaceRipple(Canvas canvas, double cx, double cy,
      double orbR, Color accent, double amp) {
    if (active < 0.01) return;

    // 3 flowing lines that move across the surface when speaking.
    canvas.save();
    canvas.translate(cx, cy);
    for (int i = 0; i < 3; i++) {
      final dir = i == 0 ? 1.0 : (i == 1 ? -0.7 : 0.5);
      final angle = time * 0.3 * dir + i * math.pi * 2 / 3;
      final arcRadius = orbR * (0.55 + i * 0.10);
      final sweep = math.pi * (0.35 + 0.15 * amp * active);
      final alpha = (0.06 + 0.14 * responding + 0.10 * amp) * active;
      if (alpha < 0.01) continue;

      canvas.save();
      canvas.rotate(angle);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: arcRadius),
        0,
        sweep,
        false,
        Paint()
          ..shader = ui.Gradient.sweep(
            Offset.zero,
            [
              _white.withValues(alpha: 0),
              _white.withValues(alpha: alpha),
              accent.withValues(alpha: alpha * 0.5),
              _white.withValues(alpha: 0),
            ],
            [0.0, 0.15, 0.35, 0.55],
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = orbR * (0.06 + 0.04 * amp * active)
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.03),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  // ── Morphed blob path ────────────────────────────────────────────

  Path _morphedPath(double cx, double cy, double orbR, double amp) {
    // When idle, minimal morph. When active/responding, more organic wobble.
    final morphStrength =
        0.015 + 0.025 * active + 0.04 * amp * active + 0.015 * responding;

    const n = 80;
    final radii = List<double>.generate(n, (i) {
      final a = (i / n) * math.pi * 2;
      final w1 = math.sin(a * 3 + time * 0.5) * morphStrength;
      final w2 = math.sin(a * 5 - time * 0.35) * morphStrength * 0.5;
      final w3 = math.cos(a * 2 + time * 0.8) * morphStrength * 0.35;
      // Audio-driven high-frequency wobble (only during speech).
      final w4 = math.sin(a * 8 + time * 2.0) * morphStrength * 0.2 * amp;
      return orbR * (1.0 + w1 + w2 + w3 + w4);
    });

    final path = Path();
    for (int i = 0; i < n; i++) {
      final a0 = (i / n) * math.pi * 2;
      final a1 = ((i + 1) % n / n) * math.pi * 2;
      final r0 = radii[i];
      final r1 = radii[(i + 1) % n];
      final x0 = cx + math.cos(a0) * r0;
      final y0 = cy + math.sin(a0) * r0;
      final x1 = cx + math.cos(a1) * r1;
      final y1 = cy + math.sin(a1) * r1;
      if (i == 0) path.moveTo(x0, y0);
      final midA = (a0 + a1) / 2;
      final midR = (r0 + r1) / 2;
      final mx = cx + math.cos(midA) * midR;
      final my = cy + math.sin(midA) * midR;
      path.quadraticBezierTo(mx, my, x1, y1);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_DarkOrbPainter o) => true;
}
