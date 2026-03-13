import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Futuristic AI orb with mode-aware colors, holographic effects,
/// energy arcs, nucleus core, and particle constellation.
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
      duration: const Duration(seconds: 60),
    )..repeat();
    _activeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _respondCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
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
            painter: _FuturisticOrbPainter(
              time: _clock.value * 60.0,
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

class _OrbPalette {
  const _OrbPalette({
    required this.core,
    required this.mid,
    required this.rim,
    required this.glow,
    required this.accent,
  });
  final Color core;
  final Color mid;
  final Color rim;
  final Color glow;
  final Color accent;

  static const defaultPalette = _OrbPalette(
    core: Color(0xFFFFFFFF),
    mid: Color(0xFFB0D4F1),
    rim: Color(0xFF4A8EC9),
    glow: Color(0xFF6BA3D6),
    accent: Color(0xFF8ABFE0),
  );

  static _OrbPalette fromColor(Color? c) {
    if (c == null) return defaultPalette;
    final hue = HSLColor.fromColor(c).hue;
    if (hue >= 250 && hue < 310) {
      return const _OrbPalette(
        core: Color(0xFFF0E8FF),
        mid: Color(0xFFB48CFF),
        rim: Color(0xFF7C5CFC),
        glow: Color(0xFF9B7AFF),
        accent: Color(0xFFD4BBFF),
      );
    }
    if (hue >= 80 && hue < 170) {
      return const _OrbPalette(
        core: Color(0xFFE8FFF0),
        mid: Color(0xFF5CDB95),
        rim: Color(0xFF05C46B),
        glow: Color(0xFF00D4AA),
        accent: Color(0xFF8AFFC5),
      );
    }
    if (hue >= 20 && hue < 55) {
      return const _OrbPalette(
        core: Color(0xFFFFF8F0),
        mid: Color(0xFFFFA94D),
        rim: Color(0xFFE8943A),
        glow: Color(0xFFC98B4E),
        accent: Color(0xFFFFD4A0),
      );
    }
    if (hue >= 190 && hue < 250) {
      return const _OrbPalette(
        core: Color(0xFFE8F4FD),
        mid: Color(0xFF5CABF7),
        rim: Color(0xFF3498DB),
        glow: Color(0xFF4A8EC9),
        accent: Color(0xFF8EC7F7),
      );
    }
    if (hue >= 330 || hue < 20) {
      return const _OrbPalette(
        core: Color(0xFFFFF0F0),
        mid: Color(0xFFFF6B6B),
        rim: Color(0xFFEE5A24),
        glow: Color(0xFFFF8A80),
        accent: Color(0xFFFFB8B8),
      );
    }
    return defaultPalette;
  }
}

class _FuturisticOrbPainter extends CustomPainter {
  _FuturisticOrbPainter({
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
  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = size.width * 0.30;
    final amp = amplitude.clamp(0.0, 1.0);
    final orbR = baseR * (1.0 + 0.06 * active + 0.16 * amp * active);
    final p = _OrbPalette.fromColor(modeColor);

    _paintDeepAura(canvas, cx, cy, orbR, p);
    if (active > 0.01) _paintPulseWaves(canvas, cx, cy, orbR, p, amp);
    if (active > 0.01) _paintRotatingHalos(canvas, cx, cy, orbR, p, amp);
    if (active > 0.01) _paintHolographicRing(canvas, cx, cy, orbR, p);
    if (active > 0.01) _paintParticles(canvas, cx, cy, orbR, p, amp);
    _paintMorphCore(canvas, cx, cy, orbR, p, amp);
    if (responding > 0.1) _paintEnergyArcs(canvas, cx, cy, orbR, p, amp);
    _paintPlasmaSwirl(canvas, cx, cy, orbR, p, amp);
    _paintNucleus(canvas, cx, cy, orbR, p, amp);
    _paintSpecular(canvas, cx, cy, orbR);
    _paintEdgeShimmer(canvas, cx, cy, orbR, p);
  }

  void _paintDeepAura(
      Canvas canvas, double cx, double cy, double orbR, _OrbPalette p) {
    final breathe = math.sin(time * 0.6) * 0.5 + 0.5;
    final breathe2 = math.sin(time * 0.9 + 1.5) * 0.5 + 0.5;
    final r1 = orbR * (2.4 + 0.2 * breathe);
    canvas.drawCircle(
      Offset(cx, cy),
      r1,
      Paint()
        ..shader = ui.Gradient.radial(Offset(cx, cy), r1, [
          p.glow.withValues(alpha: 0.06 + 0.04 * active),
          p.mid.withValues(alpha: 0.03 + 0.03 * active),
          p.rim.withValues(alpha: 0.01),
          p.core.withValues(alpha: 0)
        ], [
          0.0,
          0.3,
          0.6,
          1.0
        ])
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.6),
    );
    final r2 = orbR * (1.6 + 0.12 * breathe2);
    canvas.drawCircle(
      Offset(cx, cy),
      r2,
      Paint()
        ..shader = ui.Gradient.radial(Offset(cx, cy), r2, [
          p.accent.withValues(alpha: 0.10 * active + 0.04 * responding),
          p.glow.withValues(alpha: 0.04 * active),
          p.core.withValues(alpha: 0)
        ], [
          0.0,
          0.4,
          1.0
        ])
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.35),
    );
    if (responding > 0.01) {
      final r3 = orbR * (1.8 + 0.25 * breathe * responding);
      canvas.drawCircle(
        Offset(cx, cy),
        r3,
        Paint()
          ..shader = ui.Gradient.radial(Offset(cx, cy), r3, [
            p.core.withValues(alpha: 0.08 * responding),
            p.accent.withValues(alpha: 0.04 * responding),
            p.core.withValues(alpha: 0)
          ])
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.5),
      );
    }
  }

  void _paintPulseWaves(Canvas canvas, double cx, double cy, double orbR,
      _OrbPalette p, double amp) {
    for (int i = 0; i < 4; i++) {
      final phase = (time * 0.8 + i * 0.55) % 2.5;
      final t = (phase / 2.5).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      final r = orbR * (1.0 + eased * 1.0 + 0.2 * amp * active * (1.0 - eased));
      final fade = math.pow(1.0 - eased, 1.5).toDouble();
      final alpha = fade * 0.25 * active * (0.4 + 0.6 * amp);
      if (alpha < 0.005) continue;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = p.glow.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (2.5 * fade + 0.5) * (1.0 + 0.3 * amp)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 2 * eased),
      );
    }
  }

  void _paintRotatingHalos(Canvas canvas, double cx, double cy, double orbR,
      _OrbPalette p, double amp) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.save();
    canvas.rotate(time * 0.4);
    canvas.drawCircle(
      Offset.zero,
      orbR * 1.45,
      Paint()
        ..shader = ui.Gradient.sweep(Offset.zero, [
          p.rim.withValues(alpha: 0.0),
          p.glow.withValues(alpha: 0.30 * active),
          p.mid.withValues(alpha: 0.40 * active),
          p.accent.withValues(alpha: 0.35 * active),
          p.rim.withValues(alpha: 0.0),
          p.glow.withValues(alpha: 0.15 * active),
          p.rim.withValues(alpha: 0.0)
        ], [
          0.0,
          0.12,
          0.28,
          0.45,
          0.6,
          0.8,
          1.0
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * 0.07 + orbR * 0.03 * amp
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.04),
    );
    canvas.restore();
    canvas.save();
    canvas.rotate(-time * 0.55);
    canvas.drawCircle(
      Offset.zero,
      orbR * 1.28,
      Paint()
        ..shader = ui.Gradient.sweep(Offset.zero, [
          p.accent.withValues(alpha: 0.0),
          _white.withValues(alpha: 0.10 * active),
          p.mid.withValues(alpha: 0.20 * active),
          _white.withValues(alpha: 0.12 * active),
          p.accent.withValues(alpha: 0.0)
        ], [
          0.0,
          0.2,
          0.5,
          0.7,
          1.0
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * 0.03
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.025),
    );
    canvas.restore();
    canvas.save();
    canvas.rotate(time * 0.9);
    canvas.drawCircle(
      Offset.zero,
      orbR * 1.60,
      Paint()
        ..shader = ui.Gradient.sweep(Offset.zero, [
          p.rim.withValues(alpha: 0.0),
          p.glow.withValues(alpha: 0.08 * active),
          p.rim.withValues(alpha: 0.0),
          p.accent.withValues(alpha: 0.06 * active),
          p.rim.withValues(alpha: 0.0),
          p.glow.withValues(alpha: 0.10 * active),
          p.rim.withValues(alpha: 0.0)
        ], [
          0.0,
          0.15,
          0.3,
          0.5,
          0.65,
          0.85,
          1.0
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * 0.015
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.02),
    );
    canvas.restore();
    canvas.restore();
  }

  void _paintHolographicRing(
      Canvas canvas, double cx, double cy, double orbR, _OrbPalette p) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-time * 0.25);
    canvas.drawCircle(
      Offset.zero,
      orbR * 1.05,
      Paint()
        ..shader = ui.Gradient.sweep(Offset.zero, [
          const Color(0xFFFF6B6B).withValues(alpha: 0.12 * active),
          const Color(0xFFFFD93D).withValues(alpha: 0.10 * active),
          const Color(0xFF6BCB77).withValues(alpha: 0.12 * active),
          const Color(0xFF4D96FF).withValues(alpha: 0.10 * active),
          const Color(0xFFC084FC).withValues(alpha: 0.12 * active),
          const Color(0xFFFF6B6B).withValues(alpha: 0.10 * active)
        ], [
          0.0,
          0.2,
          0.4,
          0.6,
          0.8,
          1.0
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * 0.025
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.015),
    );
    canvas.restore();
  }

  void _paintParticles(Canvas canvas, double cx, double cy, double orbR,
      _OrbPalette p, double amp) {
    const count = 32;
    final rng = math.Random(42);
    for (int i = 0; i < count; i++) {
      final baseAngle = (i / count) * math.pi * 2;
      final dist = 0.55 + rng.nextDouble() * 0.6;
      final speed = 0.1 + rng.nextDouble() * 0.25;
      final pSize = 0.8 + rng.nextDouble() * 2.5;
      final angle = baseAngle + time * speed;
      final audioBoost = amp * active * 0.15 * math.sin(time * 2.0 + i);
      final r = orbR *
          (1.15 +
              dist * 0.55 +
              0.1 * math.sin(time * 1.3 + i * 0.8) +
              audioBoost);
      final px = cx + math.cos(angle) * r;
      final py = cy + math.sin(angle) * r;
      final twinkle = math.sin(time * 4.0 + i * 1.7) * 0.5 + 0.5;
      final alpha = (0.12 + 0.45 * twinkle) * active;
      if (alpha < 0.01) continue;
      final particleColor =
          i % 3 == 0 ? p.accent : (i % 3 == 1 ? _white : p.glow);
      canvas.drawCircle(
        Offset(px, py),
        pSize * (0.7 + 0.5 * twinkle),
        Paint()
          ..color = particleColor.withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, pSize * 0.9),
      );
      if (i > 0 && i % 4 == 0) {
        final prevAngle = ((i - 3) / count) * math.pi * 2 +
            time * (0.1 + rng.nextDouble() * 0.15);
        final prevDist = orbR * (1.15 + (0.55 + rng.nextDouble() * 0.4) * 0.55);
        final prevPx = cx + math.cos(prevAngle) * prevDist;
        final prevPy = cy + math.sin(prevAngle) * prevDist;
        canvas.drawLine(
          Offset(px, py),
          Offset(prevPx, prevPy),
          Paint()
            ..color = p.accent.withValues(alpha: 0.05 * active * twinkle)
            ..strokeWidth = 0.5,
        );
      }
    }
  }

  void _paintMorphCore(Canvas canvas, double cx, double cy, double orbR,
      _OrbPalette p, double amp) {
    final path = _buildMorphPath(cx, cy, orbR, amp);
    final gradCenter = Offset(cx - orbR * 0.22, cy - orbR * 0.20);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
            gradCenter,
            orbR * 1.1,
            responding > 0.3
                ? [
                    _white,
                    Color.lerp(p.core, _white, 0.5)!,
                    Color.lerp(p.mid, p.accent, responding * 0.5)!,
                    p.mid,
                    p.rim
                  ]
                : [p.core, _white.withValues(alpha: 0.9), p.mid, p.glow, p.rim],
            [0.0, 0.18, 0.42, 0.7, 1.0]),
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy + orbR * 0.85),
          width: orbR * 1.4,
          height: orbR * 0.12),
      Paint()
        ..color = p.rim.withValues(alpha: 0.06)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
            Offset(cx + orbR * 0.15, cy + orbR * 0.1), orbR, [
          p.accent.withValues(alpha: 0.0),
          p.rim.withValues(alpha: 0.08 * active),
          p.glow.withValues(alpha: 0.15 * active)
        ], [
          0.0,
          0.5,
          1.0
        ]),
    );
  }

  Path _buildMorphPath(double cx, double cy, double orbR, double amp) {
    const points = 64;
    final morphAmt = 0.04 + 0.06 * active + 0.08 * amp * active;
    final radii = <double>[];
    for (int i = 0; i < points; i++) {
      final angle = (i / points) * math.pi * 2;
      final w1 = math.sin(angle * 3 + time * 1.0) * morphAmt;
      final w2 = math.sin(angle * 5 - time * 0.7) * morphAmt * 0.5;
      final w3 = math.sin(angle * 7 + time * 1.8) * morphAmt * 0.3;
      final w4 = math.cos(angle * 2 - time * 0.4) * morphAmt * 0.35;
      final w5 = math.sin(angle * 11 + time * 2.5) * morphAmt * 0.15;
      radii.add(orbR * (1.0 + w1 + w2 + w3 + w4 + w5));
    }
    final path = Path();
    for (int i = 0; i < points; i++) {
      final angle = (i / points) * math.pi * 2;
      final nextAngle = ((i + 1) % points / points) * math.pi * 2;
      final r = radii[i];
      final nextR = radii[(i + 1) % points];
      final x = cx + math.cos(angle) * r;
      final y = cy + math.sin(angle) * r;
      final nx = cx + math.cos(nextAngle) * nextR;
      final ny = cy + math.sin(nextAngle) * nextR;
      if (i == 0) path.moveTo(x, y);
      final midAngle = (angle + nextAngle) / 2;
      final midR = (r + nextR) / 2 * (1.0 + morphAmt * 0.15);
      final mx = cx + math.cos(midAngle) * midR;
      final my = cy + math.sin(midAngle) * midR;
      path.quadraticBezierTo(mx, my, nx, ny);
    }
    path.close();
    return path;
  }

  void _paintEnergyArcs(Canvas canvas, double cx, double cy, double orbR,
      _OrbPalette p, double amp) {
    canvas.save();
    canvas.translate(cx, cy);
    for (int i = 0; i < 5; i++) {
      final angle = time * (0.6 + i * 0.15) + i * math.pi * 0.4;
      final reach = orbR * (0.6 + 0.25 * math.sin(time * 2.5 + i));
      canvas.save();
      canvas.rotate(angle);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: reach),
        0,
        math.pi * (0.4 + 0.3 * math.sin(time * 3.0 + i)),
        false,
        Paint()
          ..shader = ui.Gradient.sweep(Offset.zero, [
            p.accent.withValues(alpha: 0.0),
            p.core.withValues(alpha: 0.25 * responding),
            p.accent.withValues(alpha: 0.35 * responding),
            p.glow.withValues(alpha: 0.20 * responding),
            p.accent.withValues(alpha: 0.0)
          ], [
            0.0,
            0.1,
            0.25,
            0.4,
            0.6
          ])
          ..style = PaintingStyle.stroke
          ..strokeWidth = orbR * 0.04 + orbR * 0.02 * amp
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.03),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintPlasmaSwirl(Canvas canvas, double cx, double cy, double orbR,
      _OrbPalette p, double amp) {
    canvas.save();
    canvas.translate(cx, cy);
    for (int i = 0; i < 3; i++) {
      final dir = i == 0 ? 1.0 : (i == 1 ? -1.0 : 0.7);
      final angle = time * 0.6 * dir + i * math.pi * 0.45;
      final arcAmp = 0.03 + responding * 0.05 + amp * 0.04 * active;
      canvas.save();
      canvas.rotate(angle);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: orbR * (0.5 + i * 0.08)),
        0,
        math.pi * (0.6 + 0.2 * math.sin(time + i)),
        false,
        Paint()
          ..shader = ui.Gradient.sweep(Offset.zero, [
            _white.withValues(alpha: 0.0),
            _white.withValues(
                alpha: (0.15 + 0.1 * responding) * active.clamp(0.2, 1.0)),
            p.core.withValues(alpha: 0.10 + 0.08 * responding),
            _white.withValues(alpha: 0.0)
          ], [
            0.0,
            0.12,
            0.3,
            0.55
          ])
          ..style = PaintingStyle.stroke
          ..strokeWidth = orbR * (0.10 + arcAmp)
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.04),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintNucleus(Canvas canvas, double cx, double cy, double orbR,
      _OrbPalette p, double amp) {
    final beat1 = math.sin(time * 3.0) * 0.5 + 0.5;
    final beat2 = math.sin(time * 3.0 + 0.3) * 0.5 + 0.5;
    final pulse = beat1 * 0.7 + beat2 * 0.3;
    final coreR = orbR * (0.12 + 0.04 * pulse * active + 0.03 * amp * active);
    canvas.drawCircle(
      Offset(cx, cy),
      coreR,
      Paint()
        ..shader = ui.Gradient.radial(Offset(cx, cy), coreR, [
          _white.withValues(alpha: 0.95),
          p.core.withValues(alpha: 0.7 + 0.3 * active),
          p.mid.withValues(alpha: 0.3)
        ], [
          0.0,
          0.5,
          1.0
        ])
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, coreR * 0.3),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      coreR * 2.5,
      Paint()
        ..shader = ui.Gradient.radial(Offset(cx, cy), coreR * 2.5, [
          p.accent.withValues(alpha: 0.15 * active * (0.5 + 0.5 * pulse)),
          p.glow.withValues(alpha: 0.05 * active),
          p.core.withValues(alpha: 0)
        ])
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, coreR),
    );
  }

  void _paintSpecular(Canvas canvas, double cx, double cy, double orbR) {
    final hlx = cx - orbR * 0.22;
    final hly = cy - orbR * 0.24;
    final hlR = orbR * 0.38;
    canvas.drawCircle(
      Offset(hlx, hly),
      hlR,
      Paint()
        ..shader = ui.Gradient.radial(Offset(hlx, hly), hlR, [
          _white.withValues(alpha: 0.85),
          _white.withValues(alpha: 0.35),
          _white.withValues(alpha: 0.0)
        ], [
          0.0,
          0.35,
          1.0
        ]),
    );
    canvas.drawCircle(
      Offset(cx + orbR * 0.28, cy + orbR * 0.32),
      orbR * 0.10,
      Paint()
        ..shader = ui.Gradient.radial(
            Offset(cx + orbR * 0.28, cy + orbR * 0.32),
            orbR * 0.10,
            [_white.withValues(alpha: 0.22), _white.withValues(alpha: 0.0)]),
    );
    canvas.drawCircle(
      Offset(cx - orbR * 0.05, cy - orbR * 0.35),
      orbR * 0.15,
      Paint()
        ..shader = ui.Gradient.radial(
            Offset(cx - orbR * 0.05, cy - orbR * 0.35),
            orbR * 0.15,
            [_white.withValues(alpha: 0.15), _white.withValues(alpha: 0.0)]),
    );
  }

  void _paintEdgeShimmer(
      Canvas canvas, double cx, double cy, double orbR, _OrbPalette p) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(time * 0.2);
    canvas.drawCircle(
      Offset.zero,
      orbR * 0.98,
      Paint()
        ..shader = ui.Gradient.sweep(Offset.zero, [
          _white.withValues(alpha: 0.0),
          _white.withValues(alpha: 0.50),
          p.core.withValues(alpha: 0.35),
          p.mid.withValues(alpha: 0.20),
          _white.withValues(alpha: 0.0),
          _white.withValues(alpha: 0.0),
          _white.withValues(alpha: 0.30),
          p.accent.withValues(alpha: 0.15),
          _white.withValues(alpha: 0.0)
        ], [
          0.0,
          0.06,
          0.12,
          0.20,
          0.38,
          0.55,
          0.68,
          0.78,
          1.0
        ])
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * 0.035
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.015),
    );
    canvas.restore();
    canvas.drawCircle(
      Offset(cx, cy),
      orbR,
      Paint()
        ..shader = ui.Gradient.radial(Offset(cx, cy), orbR, [
          p.core.withValues(alpha: 0.0),
          p.core.withValues(alpha: 0.0),
          p.mid.withValues(alpha: 0.12 + 0.12 * active)
        ], [
          0.0,
          0.82,
          1.0
        ]),
    );
  }

  @override
  bool shouldRepaint(_FuturisticOrbPainter o) => true;
}
