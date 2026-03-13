import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A premium AI orb with flowing aurora bands, inner radiance,
/// pulsing emanations, and floating particles.
///
/// Audio-reactive and mode-color-aware. Designed for visual impact.
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
  if (c == null) return const Color(0xFF7C74A8); // brand purple
  final hue = HSLColor.fromColor(c).hue;
  if (hue >= 250 && hue < 310) return const Color(0xFF9B7AFF); // purple
  if (hue >= 80 && hue < 170) return const Color(0xFF3DDC97); // green
  if (hue >= 20 && hue < 55) return const Color(0xFFFF9F43); // orange
  if (hue >= 190 && hue < 250) return const Color(0xFF4A8EC9); // blue
  if (hue >= 330 || hue < 20) return const Color(0xFFFF6B6B); // red
  return const Color(0xFF7C74A8);
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

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = size.width * 0.34;
    final amp = amplitude.clamp(0.0, 1.0);
    final accent = _accentFromMode(modeColor);
    final hsl = HSLColor.fromColor(accent);
    final accent2 = hsl.withHue((hsl.hue + 45) % 360).toColor();
    final accent3 = hsl
        .withHue((hsl.hue + 200) % 360)
        .withSaturation(0.45)
        .withLightness(0.55)
        .toColor();

    // Audio-reactive radius — more dramatic scaling.
    final orbR = baseR * (1.0 + 0.04 * active + 0.14 * amp * active);

    _drawAmbientGlow(canvas, cx, cy, orbR, accent, accent2);
    _drawShadow(canvas, cx, cy, orbR, accent);
    _drawPulseRings(canvas, cx, cy, orbR, accent, amp);
    _drawCoreSphere(canvas, cx, cy, orbR, accent, accent2, amp);
    _drawAuroraBands(canvas, cx, cy, orbR, accent, accent2, accent3, amp);
    _drawRimLight(canvas, cx, cy, orbR, accent, accent2, amp);
    _drawSpecular(canvas, cx, cy, orbR);
    _drawParticles(canvas, cx, cy, orbR, accent);
  }

  // ── 1. Rich ambient glow ─────────────────────────────────────────

  void _drawAmbientGlow(Canvas canvas, double cx, double cy, double orbR,
      Color accent, Color accent2) {
    final breathe = math.sin(time * 0.4) * 0.5 + 0.5;

    // Primary glow.
    final glowR = orbR * (1.8 + 0.12 * breathe + 0.2 * responding);
    final glowAlpha = 0.08 + 0.12 * active + 0.08 * responding;
    canvas.drawCircle(
      Offset(cx, cy),
      glowR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          glowR,
          [
            accent.withValues(alpha: glowAlpha),
            accent.withValues(alpha: glowAlpha * 0.5),
            accent2.withValues(alpha: glowAlpha * 0.15),
            accent.withValues(alpha: 0),
          ],
          [0.0, 0.3, 0.6, 1.0],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.6),
    );

    // Secondary warm glow (offset for asymmetry).
    final g2Alpha = 0.03 + 0.06 * active;
    canvas.drawCircle(
      Offset(cx + orbR * 0.2, cy - orbR * 0.1),
      orbR * 1.3,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx + orbR * 0.2, cy - orbR * 0.1),
          orbR * 1.3,
          [
            accent2.withValues(alpha: g2Alpha),
            accent2.withValues(alpha: 0),
          ],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.5),
    );
  }

  // ── 2. Drop shadow ──────────────────────────────────────────────

  void _drawShadow(
      Canvas canvas, double cx, double cy, double orbR, Color accent) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + orbR * 0.9),
        width: orbR * 1.4,
        height: orbR * 0.18,
      ),
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.35),
    );
    // Colored shadow hint.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + orbR * 0.85),
        width: orbR * 1.0,
        height: orbR * 0.10,
      ),
      Paint()
        ..color = accent.withValues(alpha: 0.06 * active)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.25),
    );
  }

  // ── 3. Pulse rings (audio-reactive emanations) ──────────────────

  void _drawPulseRings(Canvas canvas, double cx, double cy, double orbR,
      Color accent, double amp) {
    if (active < 0.01) return;

    for (int i = 0; i < 3; i++) {
      final phase = (time * 0.6 + i * 1.2) % 3.6;
      final t = phase / 3.6; // 0‥1 lifecycle
      final ringR = orbR * (1.1 + 0.8 * t);
      final fadeAlpha = (1.0 - t) * (0.08 + 0.12 * amp) * active;
      if (fadeAlpha < 0.005) continue;

      canvas.drawCircle(
        Offset(cx, cy),
        ringR,
        Paint()
          ..color = accent.withValues(alpha: fadeAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = orbR * 0.02 * (1.0 - t * 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.04),
      );
    }
  }

  // ── 4. Core sphere (morphed, inner radiance) ────────────────────

  void _drawCoreSphere(Canvas canvas, double cx, double cy, double orbR,
      Color accent, Color accent2, double amp) {
    final path = _morphedPath(cx, cy, orbR, amp);

    // Deep dark base with subtle gradient.
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx - orbR * 0.1, cy - orbR * 0.1),
          orbR * 1.3,
          [
            const Color(0xFF1A1A28),
            const Color(0xFF0F0F18),
            const Color(0xFF080810),
          ],
          [0.0, 0.5, 1.0],
        ),
    );

    // Inner radiance — breathing, rotating.
    final breathe = math.sin(time * 0.35) * 0.5 + 0.5;
    final innerAlpha =
        0.06 + 0.10 * active + 0.08 * responding + 0.04 * breathe;

    final angle = time * 0.15;
    final ix = cx + math.cos(angle) * orbR * 0.15;
    final iy = cy + math.sin(angle) * orbR * 0.15;

    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(ix, iy),
          orbR * 0.9,
          [
            accent.withValues(alpha: innerAlpha),
            accent2.withValues(alpha: innerAlpha * 0.5),
            accent.withValues(alpha: innerAlpha * 0.2),
            accent.withValues(alpha: 0),
          ],
          [0.0, 0.3, 0.6, 1.0],
        ),
    );

    // Audio-reactive bright core flash.
    if (amp > 0.1 && active > 0.5) {
      final flashAlpha = amp * 0.12 * active;
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            orbR * 0.6,
            [
              accent.withValues(alpha: flashAlpha),
              accent.withValues(alpha: 0),
            ],
          ),
      );
    }
  }

  // ── 5. Aurora bands (flowing light arcs) ────────────────────────

  void _drawAuroraBands(Canvas canvas, double cx, double cy, double orbR,
      Color accent, Color accent2, Color accent3, double amp) {
    canvas.save();
    canvas.clipPath(_morphedPath(cx, cy, orbR * 0.98, amp));

    const bandCount = 5;
    for (int i = 0; i < bandCount; i++) {
      final speed = 0.2 + i * 0.08;
      final dir = i.isEven ? 1.0 : -1.0;
      final baseAngle = time * speed * dir + i * math.pi * 2 / bandCount;

      // Cycle through accent variations.
      final bandColor = i % 3 == 0 ? accent : (i % 3 == 1 ? accent2 : accent3);

      final bandAlpha =
          (0.04 + 0.10 * active + 0.08 * responding + 0.06 * amp) *
              (0.6 + 0.4 * math.sin(time * 0.3 + i * 1.5).abs());
      if (bandAlpha < 0.01) continue;

      final arcR = orbR * (0.4 + i * 0.12);
      final sweep = math.pi * (0.5 + 0.3 * amp * active);
      final yShift = math.sin(time * 0.25 + i) * orbR * 0.2;

      canvas.save();
      canvas.translate(cx, cy + yShift);
      canvas.rotate(baseAngle);

      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: arcR),
        0,
        sweep,
        false,
        Paint()
          ..shader = ui.Gradient.sweep(
            Offset.zero,
            [
              bandColor.withValues(alpha: 0),
              bandColor.withValues(alpha: bandAlpha),
              bandColor.withValues(alpha: bandAlpha * 0.7),
              bandColor.withValues(alpha: 0),
            ],
            [0.0, 0.2, 0.5, 0.8],
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = orbR * (0.10 + 0.06 * amp * active)
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.05),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  // ── 6. Rim light ────────────────────────────────────────────────

  void _drawRimLight(Canvas canvas, double cx, double cy, double orbR,
      Color accent, Color accent2, double amp) {
    final path = _morphedPath(cx, cy, orbR, amp);

    // Inner rim glow.
    final rimAlpha = 0.15 + 0.20 * active + 0.12 * responding;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          orbR,
          [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0),
            accent.withValues(alpha: rimAlpha * 0.5),
            accent.withValues(alpha: rimAlpha),
          ],
          [0.0, 0.65, 0.85, 1.0],
        ),
    );

    // Animated dual-color rim stroke.
    final strokeW = orbR * 0.025 + orbR * 0.015 * amp * active;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.sweep(
          Offset(cx, cy),
          [
            accent.withValues(alpha: 0.0),
            accent.withValues(alpha: 0.40 * active + 0.12),
            accent2.withValues(alpha: 0.25 * active + 0.08),
            const Color(0xFFFFFFFF).withValues(alpha: 0.10 * active),
            accent.withValues(alpha: 0.35 * active + 0.10),
            accent.withValues(alpha: 0.0),
          ],
          [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.015),
    );
  }

  // ── 7. Glass specular highlight (refined) ───────────────────────

  void _drawSpecular(Canvas canvas, double cx, double cy, double orbR) {
    // Primary — crisp but not overpowering.
    final hlx = cx - orbR * 0.22;
    final hly = cy - orbR * 0.26;
    final hlR = orbR * 0.28;
    canvas.drawCircle(
      Offset(hlx, hly),
      hlR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(hlx, hly),
          hlR,
          [
            const Color(0xFFFFFFFF).withValues(alpha: 0.35),
            const Color(0xFFFFFFFF).withValues(alpha: 0.10),
            const Color(0xFFFFFFFF).withValues(alpha: 0),
          ],
          [0.0, 0.35, 1.0],
        ),
    );

    // Secondary — subtle bottom reflection.
    final h2x = cx + orbR * 0.18;
    final h2y = cy + orbR * 0.20;
    canvas.drawCircle(
      Offset(h2x, h2y),
      orbR * 0.06,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(h2x, h2y),
          orbR * 0.06,
          [
            const Color(0xFFFFFFFF).withValues(alpha: 0.08),
            const Color(0xFFFFFFFF).withValues(alpha: 0),
          ],
        ),
    );
  }

  // ── 8. Floating particles ───────────────────────────────────────

  void _drawParticles(
      Canvas canvas, double cx, double cy, double orbR, Color accent) {
    if (active < 0.05) return;

    const count = 10;
    for (int i = 0; i < count; i++) {
      // Deterministic orbit via golden-angle spacing.
      final seed = i * 137.508;
      final orbitR = orbR * (1.15 + 0.25 * math.sin(seed));
      final speed = 0.12 + 0.08 * math.sin(seed * 2.3);
      final phase = seed + time * speed;

      final px = cx + math.cos(phase) * orbitR;
      final py = cy + math.sin(phase * 0.7 + seed) * orbitR * 0.6;

      // Pulsing size and alpha.
      final pulse = math.sin(time * 1.5 + seed) * 0.5 + 0.5;
      final pAlpha = (0.15 + 0.25 * pulse) * active;
      final pR = orbR * (0.012 + 0.008 * pulse);

      canvas.drawCircle(
        Offset(px, py),
        pR,
        Paint()
          ..color = accent.withValues(alpha: pAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, pR * 1.5),
      );
    }
  }

  // ── Morphed blob path (more dramatic) ───────────────────────────

  Path _morphedPath(double cx, double cy, double orbR, double amp) {
    final morphStrength =
        0.025 + 0.04 * active + 0.06 * amp * active + 0.025 * responding;

    const n = 80;
    final radii = List<double>.generate(n, (i) {
      final a = (i / n) * math.pi * 2;
      final w1 = math.sin(a * 3 + time * 0.5) * morphStrength;
      final w2 = math.sin(a * 5 - time * 0.35) * morphStrength * 0.6;
      final w3 = math.cos(a * 2 + time * 0.8) * morphStrength * 0.4;
      final w4 = math.sin(a * 7 + time * 1.5) * morphStrength * 0.25;
      // Audio-driven high-freq wobble.
      final w5 = math.sin(a * 10 + time * 2.5) * morphStrength * 0.3 * amp;
      return orbR * (1.0 + w1 + w2 + w3 + w4 + w5);
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
