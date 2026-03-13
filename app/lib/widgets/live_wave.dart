import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Elite AI orb — production-grade, multi-layered with:
///   • Morphing blob shape (multi-frequency wobble)
///   • Dual rotating gradient aura
///   • Particle constellation ring
///   • Audio-reactive pulse rings
///   • Inner plasma swirl
///   • Smooth state crossfade (idle → listening → responding)
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
            painter: _EliteOrbPainter(
              time: _clock.value * 60.0,
              active: _activeCtrl.value,
              responding: _respondCtrl.value,
              amplitude: widget.amplitude,
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ELITE ORB PAINTER
// ═══════════════════════════════════════════════════════════════════════

class _EliteOrbPainter extends CustomPainter {
  _EliteOrbPainter({
    required this.time,
    required this.active,
    required this.responding,
    required this.amplitude,
  });

  final double time;
  final double active;
  final double responding;
  final double amplitude;

  // ── Color palette ──────────────────────────────────────────────────
  static const _white = Color(0xFFFFFFFF);
  static const _ice = Color(0xFFE8F4FD);
  static const _sky = Color(0xFFB0D4F1);
  static const _azure = Color(0xFF8ABFE0);
  static const _steel = Color(0xFF6BA3D6);
  static const _deep = Color(0xFF4A8EC9);
  static const _warmWhite = Color(0xFFFFF8F0);
  static const _gold = Color(0xFFC98B4E);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = size.width * 0.30;
    final amp = amplitude.clamp(0.0, 1.0);
    final orbR = baseR * (1.0 + 0.05 * active + 0.14 * amp * active);

    _paintAmbientAura(canvas, cx, cy, orbR);
    if (active > 0.01) _paintRotatingHalo(canvas, cx, cy, orbR);
    if (active > 0.01) _paintParticles(canvas, cx, cy, orbR);
    if (active > 0.01) _paintPulseRings(canvas, cx, cy, orbR);
    _paintMorphCore(canvas, cx, cy, orbR);
    _paintPlasmaSwirl(canvas, cx, cy, orbR);
    _paintSpecular(canvas, cx, cy, orbR);
    _paintEdgeShimmer(canvas, cx, cy, orbR);
  }

  // ── 1. Ambient aura ─────────────────────────────────────────────
  void _paintAmbientAura(Canvas canvas, double cx, double cy, double orbR) {
    final breathe = math.sin(time * 0.8) * 0.5 + 0.5;
    final r = orbR * (2.2 + 0.15 * breathe);
    final alpha = 0.04 + 0.03 * breathe + 0.05 * active;

    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          r,
          [
            _azure.withValues(alpha: alpha),
            _sky.withValues(alpha: alpha * 0.5),
            _ice.withValues(alpha: 0),
          ],
          [0.0, 0.5, 1.0],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.5),
    );

    if (responding > 0.01) {
      canvas.drawCircle(
        Offset(cx, cy),
        r * 0.8,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            r * 0.8,
            [
              _gold.withValues(alpha: 0.06 * responding),
              _warmWhite.withValues(alpha: 0),
            ],
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.4),
      );
    }
  }

  // ── 2. Rotating gradient halo ───────────────────────────────────
  void _paintRotatingHalo(Canvas canvas, double cx, double cy, double orbR) {
    canvas.save();
    canvas.translate(cx, cy);

    // First rotating ring
    canvas.save();
    canvas.rotate(time * 0.5);
    canvas.drawCircle(
      Offset.zero,
      orbR * 1.55,
      Paint()
        ..shader = ui.Gradient.sweep(
          Offset.zero,
          [
            _sky.withValues(alpha: 0.0),
            _azure.withValues(alpha: 0.18 * active),
            _steel.withValues(alpha: 0.25 * active),
            _deep.withValues(alpha: 0.20 * active),
            _sky.withValues(alpha: 0.0),
          ],
          [0.0, 0.2, 0.5, 0.8, 1.0],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * 0.08
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.06),
    );
    canvas.restore();

    // Second counter-rotating ring
    canvas.save();
    canvas.rotate(-time * 0.35);
    canvas.drawCircle(
      Offset.zero,
      orbR * 1.38,
      Paint()
        ..shader = ui.Gradient.sweep(
          Offset.zero,
          [
            _azure.withValues(alpha: 0.0),
            _ice.withValues(alpha: 0.12 * active),
            _white.withValues(alpha: 0.08 * active),
            _azure.withValues(alpha: 0.0),
          ],
          [0.0, 0.3, 0.6, 1.0],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * 0.04
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.03),
    );
    canvas.restore();

    canvas.restore();
  }

  // ── 3. Particle constellation ───────────────────────────────────
  void _paintParticles(Canvas canvas, double cx, double cy, double orbR) {
    const count = 24;
    final particleRng = math.Random(42);

    for (int i = 0; i < count; i++) {
      final baseAngle = (i / count) * math.pi * 2;
      final radiusOffset = particleRng.nextDouble() * 0.5 + 0.6;
      final speed = 0.15 + particleRng.nextDouble() * 0.3;
      final particleSize = 1.0 + particleRng.nextDouble() * 2.0;

      final angle = baseAngle + time * speed;
      final r = orbR *
          (1.2 + radiusOffset * 0.5 + 0.08 * math.sin(time * 1.5 + i * 0.7));

      final px = cx + math.cos(angle) * r;
      final py = cy + math.sin(angle) * r;

      final twinkle = math.sin(time * 3.0 + i * 1.3) * 0.5 + 0.5;
      final alpha = (0.15 + 0.35 * twinkle) * active;
      if (alpha < 0.01) continue;

      canvas.drawCircle(
        Offset(px, py),
        particleSize * (0.8 + 0.4 * twinkle),
        Paint()
          ..color = Color.lerp(_ice, _white, twinkle)!.withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, particleSize * 0.8),
      );
    }
  }

  // ── 4. Pulse rings ──────────────────────────────────────────────
  void _paintPulseRings(Canvas canvas, double cx, double cy, double orbR) {
    for (int i = 0; i < 3; i++) {
      final phase = (time * 1.2 + i * 0.7) % 2.0;
      final t = (phase / 2.0).clamp(0.0, 1.0);
      final eased = Curves.easeOut.transform(t);

      final r = orbR * (1.0 + eased * 0.7 + 0.15 * amplitude * active);
      final fade = 1.0 - eased;
      final alpha = fade * 0.3 * active * (0.5 + 0.5 * amplitude);
      if (alpha < 0.01) continue;

      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = _sky.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * fade + 0.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  // ── 5. Morphing blob core ───────────────────────────────────────
  void _paintMorphCore(Canvas canvas, double cx, double cy, double orbR) {
    final path = Path();
    const points = 80;
    final morphAmt = 0.03 + 0.05 * active + 0.06 * amplitude * active;

    for (int i = 0; i <= points; i++) {
      final angle = (i / points) * math.pi * 2;
      final w1 = math.sin(angle * 3 + time * 1.2) * morphAmt;
      final w2 = math.sin(angle * 5 - time * 0.8) * morphAmt * 0.5;
      final w3 = math.sin(angle * 7 + time * 2.0) * morphAmt * 0.25;
      final w4 = math.cos(angle * 2 - time * 0.5) * morphAmt * 0.3;

      final r = orbR * (1.0 + w1 + w2 + w3 + w4);
      final x = cx + math.cos(angle) * r;
      final y = cy + math.sin(angle) * r;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final gradCenter = Offset(cx - orbR * 0.25, cy - orbR * 0.22);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(
          gradCenter,
          orbR * 1.1,
          responding > 0.3
              ? [
                  _white,
                  Color.lerp(_ice, _warmWhite, responding)!,
                  Color.lerp(_sky, const Color(0xFFE0D0C0), responding * 0.4)!,
                  _azure,
                  _steel,
                ]
              : [_white, _ice, _sky, _azure, _steel],
          [0.0, 0.2, 0.45, 0.72, 1.0],
        ),
    );

    // Subtle shadow under the orb
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + orbR * 0.85),
        width: orbR * 1.4,
        height: orbR * 0.15,
      ),
      Paint()
        ..color = _steel.withValues(alpha: 0.06)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.3),
    );
  }

  // ── 6. Inner plasma swirl ───────────────────────────────────────
  void _paintPlasmaSwirl(Canvas canvas, double cx, double cy, double orbR) {
    canvas.save();
    canvas.translate(cx, cy);

    for (int i = 0; i < 2; i++) {
      final dir = i == 0 ? 1.0 : -1.0;
      final angle = time * 0.7 * dir + i * math.pi * 0.6;
      final arcAmp = 0.03 + responding * 0.04 + amplitude * 0.03 * active;

      canvas.save();
      canvas.rotate(angle);

      final arcPaint = Paint()
        ..shader = ui.Gradient.sweep(
          Offset.zero,
          [
            _white.withValues(alpha: 0.0),
            _white.withValues(
                alpha: (0.12 + 0.08 * responding) * active.clamp(0.3, 1.0)),
            _ice.withValues(alpha: 0.08 + 0.06 * responding),
            _white.withValues(alpha: 0.0),
          ],
          [0.0, 0.15, 0.35, 0.6],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * (0.12 + arcAmp)
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.05);

      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: orbR * 0.55),
        0,
        math.pi * 0.8,
        false,
        arcPaint,
      );
      canvas.restore();
    }

    canvas.restore();
  }

  // ── 7. Specular highlight ───────────────────────────────────────
  void _paintSpecular(Canvas canvas, double cx, double cy, double orbR) {
    final hlx = cx - orbR * 0.22;
    final hly = cy - orbR * 0.24;
    final hlR = orbR * 0.42;

    canvas.drawCircle(
      Offset(hlx, hly),
      hlR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(hlx, hly),
          hlR,
          [
            _white.withValues(alpha: 0.90),
            _white.withValues(alpha: 0.40),
            _white.withValues(alpha: 0.0),
          ],
          [0.0, 0.4, 1.0],
        ),
    );

    // Secondary micro-highlight
    final hl2x = cx + orbR * 0.28;
    final hl2y = cy + orbR * 0.30;
    canvas.drawCircle(
      Offset(hl2x, hl2y),
      orbR * 0.12,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(hl2x, hl2y),
          orbR * 0.12,
          [
            _white.withValues(alpha: 0.25),
            _white.withValues(alpha: 0.0),
          ],
        ),
    );
  }

  // ── 8. Edge shimmer ring ────────────────────────────────────────
  void _paintEdgeShimmer(Canvas canvas, double cx, double cy, double orbR) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(time * 0.3);

    canvas.drawCircle(
      Offset.zero,
      orbR * 0.98,
      Paint()
        ..shader = ui.Gradient.sweep(
          Offset.zero,
          [
            _white.withValues(alpha: 0.0),
            _white.withValues(alpha: 0.45),
            _ice.withValues(alpha: 0.30),
            _sky.withValues(alpha: 0.15),
            _white.withValues(alpha: 0.0),
            _white.withValues(alpha: 0.0),
            _white.withValues(alpha: 0.25),
            _white.withValues(alpha: 0.0),
          ],
          [0.0, 0.08, 0.15, 0.22, 0.4, 0.6, 0.75, 1.0],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = orbR * 0.04
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, orbR * 0.02),
    );
    canvas.restore();

    // Inner rim glow
    canvas.drawCircle(
      Offset(cx, cy),
      orbR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          orbR,
          [
            _white.withValues(alpha: 0.0),
            _white.withValues(alpha: 0.0),
            _ice.withValues(alpha: 0.10 + 0.10 * active),
          ],
          [0.0, 0.85, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_EliteOrbPainter o) => true;
}
