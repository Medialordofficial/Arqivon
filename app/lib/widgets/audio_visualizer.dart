import 'dart:math';

import 'package:flutter/material.dart';

/// Animated audio waveform visualiser for the Live tab.
class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    super.key,
    this.isActive = false,
    this.color,
    this.barCount = 30,
    this.height = 60,
  });

  final bool isActive;
  final Color? color;
  final int barCount;
  final double height;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isActive) _controller.repeat();
  }

  @override
  void didUpdateWidget(AudioVisualizer old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      listenable: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _WavePainter(
            progress: _controller.value,
            barCount: widget.barCount,
            color: color,
            isActive: widget.isActive,
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.progress,
    required this.barCount,
    required this.color,
    required this.isActive,
  });

  final double progress;
  final int barCount;
  final Color color;
  final bool isActive;
  final Random _rng = Random(42);

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (barCount * 2);
    final maxHeight = size.height;

    for (int i = 0; i < barCount; i++) {
      final normalised = sin((progress * 2 * pi) + (i * 0.3));
      final heightFactor = isActive
          ? 0.3 + 0.7 * ((normalised + 1) / 2) * (_rng.nextDouble() * 0.5 + 0.5)
          : 0.05;
      final barHeight = maxHeight * heightFactor;

      final paint = Paint()
        ..color = color.withOpacity(0.4 + 0.6 * heightFactor)
        ..style = PaintingStyle.fill;

      final x = i * barWidth * 2 + barWidth / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, size.height / 2),
          width: barWidth * 0.8,
          height: barHeight.clamp(2.0, maxHeight),
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => progress != old.progress;
}

/// Alias for AnimatedBuilder to fix the name
class AnimatedBuilder extends AnimatedWidget {
  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
  });

  final Widget Function(BuildContext, Widget?) builder;

  @override
  Widget build(BuildContext context) => builder(context, null);

  // Override listenable getter to use 'animation' name
  Animation get animation => super.listenable as Animation;
}
