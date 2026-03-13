import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A luminous, vibrant AI orb — glowing energy sphere with swirling
/// aurora bands, pulsing core, orbiting particles, and reactive bloom.
///
/// NOT a dark ball. This is a radiant, colorful, alive object.
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
            painter: _OrbPainter(
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
  if (c == null) return const Color(0xFF9B7AFF); // brand purple
  final hue = HSLColor.fromColor(c).hue;
  if (hue >= 250 && hue < 310) return const Color(0xFFB08DFF); // purple
  if (hue >= 80 && hue < 170) return const Color(0xFF4AEAAA); // green
  if (hue >= 20 && hue < 55) return const Color(0xFFFFB060); // orange
  if (hue >= 190 && hue < 250) return const Color(0xFF60A8E8); // blue
  if (hue >= 330 || hue < 20) return const Color(0xFFFF7878); // red
  return const Color(0xFF9B7AFF);
}

// ─── The painter ───────────────────────────────────────────────────────

class _OrbPainter extends CustomPainter {
  _OrbPainter({
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
    final baseR = size.width * 0.33;
    final amp = amplitude.clamp(0.0, 1.0);
    final accent = _accentFromMode(modeColor);
    final hsl = HSLColor.fromColor(accent);
    final accent2 =
        hsl.withHue((hsl.hue + 55) % 360).withLightness(0.65).toColor();
    final accent3 =
        hsl.withHue((hsl.hue + 180) % 360).withLightness(0.55).toColor();

    final orbR = baseR * (1.0 + 0.05 * active + 0.16 * amp * active);

    _drawOuterBloom(canvas, cx, cy, orbR, accent, accent2);
    _drawPulseRings(canvas, cx, cy, orbR, accent, amp);
    _drawGlowingSphere(canvas, cx, cy, orbR, accent, accent2, accent3, amp);
    _drawAuroraBands(canvas, cx, cy, orbR, accent, accent2, accent3, amp);
    _drawRimLight(canvas, cx, cy, orbR, accent, accent2, amp);
    _drawSpecular(canvas, cx, cy, orbR);
    _drawParticles(canvas, cx, cy, orbR, accent, accent2);
  }

  // ── 1. Outer bloom — big, bright, colorful halo ──────────────────

  void _drawOuterBloom(Canvas canvas, double cx, double cy, double orbR,
      Color accent, Color accent2) {
    final breathe = math.sin(time * 0.4) * 0.5 + 0.5;

    // Primary large glow.
    final glowR = orbR * (2.0 + 0.15 * breathe + 0.3 * responding);
    final glowA = 0.12 + 0.18 * active + 0.12 * responding;
    canvas.drawCircle(
      Offset(cx, cy),
      glowR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          glowR,
          [
            accent.withValues(alpha: glowA),
            accent.withValues(alpha: glowA * 0.6),
            accent2.withValues(alpha: glowA * 0.2),
            accent.withValues(alpha: 0),
          ],
          [0.0, 0.25, 0.55, 1.0],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.7),
    );

    // Secondary asymmetric bloom.
    final g2A = 0.06 + 0.10 * active;
    canvas.drawCircle(
      Offset(cx + orbR * 0.25, cy - orbR * 0.15),
      orbR * 1.4,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx + orbR * 0.25, cy - orbR * 0.15),
          orbR * 1.4,
          [
            accent2.withValues(alpha: g2A),
            accent2.withValues(alpha: g2A * 0.3),
            accent2.withValues(alpha: 0),
          ],
          [0.0, 0.4, 1.0],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.5),
    );
  }

  // ── 2. Pulse rings ──────────────────────────────────────────────

  void _drawPulseRings(Canvas canvas, double cx, double cy, double orbR,
      Color accent, double amp) {
    if (active < 0.01) return;

    for (int i = 0; i < 3; i++) {
      final phase = (time * 0.5 + i * 1.4) % 4.2;
      final t = phase / 4.2;
      final ringR = orbR * (1.05 + 0.9 * t);
      final fade = (1.0 - t) * (0.12 + 0.18 * amp) * active;
      if (fade < 0.005) continue;

      canvas.drawCircle(
        Offset(cx, cy),
        ringR,
        Paint()
          ..color = accent.withValues(alpha: fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = orbR * 0.025 * (1.0 - t * 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.035),
      );
    }
  }

  // ── 3. Glowing sphere — vibrant, luminous, NOT dark ─────────────

  void _drawGlowingSphere(Canvas canvas, double cx, double cy, double orbR,
      Color accent, Color accent2, Color accent3, double amp) {
    final path = _morphedPath(cx, cy, orbR, amp);

    // The key difference: the sphere itself is COLORED, not black.
    // Base: deep jewel tones of the accent color, not gray/black.
    final accentDark = HSLColor.fromColor(accent)
        .withLightness(0.12)
        .withSaturation(0.6)
        .toColor();
    final accentMid = HSLColor.fromColor(accent)
        .withLightness(0.18)
        .withSaturation(0.5)
        .toColor();

    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx - orbR * 0.1, cy - orbR * 0.1),
          orbR * 1.2,
          [accentMid, accentDark, const Color(0xFF06060C)],
          [0.0, 0.6, 1.0],
        ),
    );

    // Bright inner radiance — breathing, rotating glow.
    final breathe = math.sin(time * 0.35) * 0.5 + 0.5;
    final iA = 0.20 + 0.25 * active + 0.15 * responding + 0.08 * breathe;

    final ang = time * 0.15;
    final ix = cx + math.cos(ang) * orbR * 0.12;
    final iy = cy + math.sin(ang) * orbR * 0.12;

    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(ix, iy),
          orbR * 0.85,
          [
            accent.withValues(alpha: iA),
            accent2.withValues(alpha: iA * 0.6),
            accent3.withValues(alpha: iA * 0.25),
            accent.withValues(alpha: 0),
          ],
          [0.0, 0.3, 0.6, 1.0],
        ),
    );

    // Secondary rotating glow — opposite phase for richness.
    final ang2 = time * -0.12 + 2.0;
    final ix2 = cx + math.cos(ang2) * orbR * 0.18;
    final iy2 = cy + math.sin(ang2) * orbR * 0.18;
    final iA2 = 0.08 + 0.12 * active + 0.10 * responding;

    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(ix2, iy2),
          orbR * 0.7,
          [
            accent2.withValues(alpha: iA2),
            accent3.withValues(alpha: iA2 * 0.4),
            accent2.withValues(alpha: 0),
          ],
          [0.0, 0.4, 1.0],
        ),
    );

    // Audio-reactive core flash — bright burst when speaking.
    if (amp > 0.05 && active > 0.3) {
      final flash = amp * 0.25 * active;
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            orbR * 0.55,
            [
              accent.withValues(alpha: flash),
              accent.withValues(alpha: flash * 0.3),
              accent.withValues(alpha: 0),
            ],
            [0.0, 0.4, 1.0],
          ),
      );
    }
  }

  // ── 4. Aurora bands — wider, brighter, more visible ─────────────

  void _drawAuroraBands(Canvas canvas, double cx, double cy, double orbR,
      Color accent, Color accent2, Color accent3, double amp) {
    canvas.save();
    canvas.clipPath(_morphedPath(cx, cy, orbR * 0.97, amp));

    const bandCount = 5;
    for (int i = 0; i < bandCount; i++) {
      final speed = 0.18 + i * 0.07;
      final dir = i.isEven ? 1.0 : -1.0;
      final baseAngle = time * speed * dir + i * math.pi * 2 / bandCount;

      final bandColor = i % 3 == 0 ? accent : (i % 3 == 1 ? accent2 : accent3);

      // Much higher alpha — these should be CLEARLY visible.
      final bandA = (0.10 + 0.20 * active + 0.15 * responding + 0.12 * amp) *
          (0.6 + 0.4 * math.sin(time * 0.3 + i * 1.5).abs());
      if (bandA < 0.01) continue;

      final arcR = orbR * (0.35 + i * 0.13);
      final sweep = math.pi * (0.6 + 0.4 * amp * active);
      final yShift = math.sin(time * 0.22 + i) * orbR * 0.18;

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
              bandColor.withValues(alpha: bandA),
              bandColor.withValues(alpha: bandA * 0.7),
              bandColor.withValues(alpha: 0),
            ],
            [0.0, 0.15, 0.45, 0.75],
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = orbR * (0.14 + 0.08 * amp * active)
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.06),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  // ── 5. Rim light — bright edge glow ─────────────────────────────

  void _drawRimLight(Canvas canvas, double cx, double cy, double orbR,
      Color accent, Color accent2, double amp) {
    final path = _morphedPath(cx, cy, orbR, amp);

    // Strong inner edge glow.
    final rimA = 0.20 + 0.30 * active + 0.18 * responding;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          orbR,
          [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0),
            accent.withValues(alpha: rimA * 0.6),
            accent.withValues(alpha: rimA),
          ],
          [0.0, 0.60, 0.82, 1.0],
        ),
    );

    // Animated bright rim stroke.
    final sw = orbR * 0.03 + orbR * 0.02 * amp * active;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.sweep(
          Offset(cx, cy),
          [
            accent.withValues(alpha: 0.05),
            accent.withValues(alpha: 0.45 * active + 0.15),
            accent2.withValues(alpha: 0.30 * active + 0.10),
            const Color(0xFFFFFFFF).withValues(alpha: 0.15 * active),
            accent.withValues(alpha: 0.40 * active + 0.12),
            accent.withValues(alpha: 0.05),
          ],
          [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.018),
    );
  }

  // ── 6. Specular ─────────────────────────────────────────────────

  void _drawSpecular(Canvas canvas, double cx, double cy, double orbR) {
    final hlx = cx - orbR * 0.20;
    final hly = cy - orbR * 0.24;
    final hlR = orbR * 0.22;
    canvas.drawCircle(
      Offset(hlx, hly),
      hlR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(hlx, hly),
          hlR,
          [
            const Color(0xFFFFFFFF).withValues(alpha: 0.30),
            const Color(0xFFFFFFFF).withValues(alpha: 0.08),
            const Color(0xFFFFFFFF).withValues(alpha: 0),
          ],
          [0.0, 0.4, 1.0],
        ),
    );
  }

  // ── 7. Orbiting particles ───────────────────────────────────────

  void _drawParticles(Canvas canvas, double cx, double cy, double orbR,
      Color accent, Color accent2) {
    if (active < 0.03) return;

    const count = 14;
    for (int i = 0; i < count; i++) {
      final seed = i * 137.508;
      final orbitR = orbR * (1.10 + 0.30 * math.sin(seed));
      final speed = 0.10 + 0.06 * math.sin(seed * 2.3);
      final phase = seed + time * speed;
      final col = i.isEven ? accent : accent2;

      final px = cx + math.cos(phase) * orbitR;
      final py = cy + math.sin(phase * 0.65 + seed) * orbitR * 0.55;

      final pulse = math.sin(time * 1.5 + seed) * 0.5 + 0.5;
      final pA = (0.25 + 0.35 * pulse) * active;
      final pR = orbR * (0.015 + 0.010 * pulse);

      canvas.drawCircle(
        Offset(px, py),
        pR,
        Paint()
          ..color = col.withValues(alpha: pA)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, pR * 1.8),
      );
    }
  }

  // ── Morphed blob path ───────────────────────────────────────────

  Path _morphedPath(double cx, double cy, double orbR, double amp) {
    final ms = 0.025 + 0.045 * active + 0.07 * amp * active + 0.03 * responding;

    const n = 80;
    final radii = List<double>.generate(n, (i) {
      final a = (i / n) * math.pi * 2;
      final w1 = math.sin(a * 3 + time * 0.5) * ms;
      final w2 = math.sin(a * 5 - time * 0.35) * ms * 0.6;
      final w3 = math.cos(a * 2 + time * 0.8) * ms * 0.4;
      final w4 = math.sin(a * 7 + time * 1.5) * ms * 0.3;
      final w5 = math.sin(a * 10 + time * 2.5) * ms * 0.35 * amp;
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
  bool shouldRepaint(_OrbPainter o) => true;
}
