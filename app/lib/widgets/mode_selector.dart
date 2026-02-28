import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent_mode.dart';

/// Horizontal mode-picker strip shown at the top of Live screen.
///
/// Features:
///   - Smooth animated transitions with easeInOutCubic curves
///   - Glow pulse effect on freshly-selected chip
///   - Medium haptic feedback on switch
///   - AnimatedDefaultTextStyle for color/weight transitions
class ModeSelectorStrip extends StatefulWidget {
  const ModeSelectorStrip({
    super.key,
    required this.selectedMode,
    required this.onModeSelected,
    this.isStreaming = false,
  });

  final AgentMode selectedMode;
  final ValueChanged<AgentMode> onModeSelected;
  final bool isStreaming;

  @override
  State<ModeSelectorStrip> createState() => _ModeSelectorStripState();
}

class _ModeSelectorStripState extends State<ModeSelectorStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  AgentMode? _lastGlowMode;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _glowAnim = CurvedAnimation(
      parent: _glowCtrl,
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(ModeSelectorStrip old) {
    super.didUpdateWidget(old);
    if (old.selectedMode != widget.selectedMode) {
      _lastGlowMode = widget.selectedMode;
      _glowCtrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: AgentMode.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mode = AgentMode.values[index];
          final isSelected = mode == widget.selectedMode;
          final isGlowing = _lastGlowMode == mode;

          return Semantics(
            label: '${mode.label} mode${isSelected ? ", selected" : ""}',
            button: true,
            selected: isSelected,
            child: GestureDetector(
              onTap: () {
                if (mode == widget.selectedMode) return;
                HapticFeedback.mediumImpact();
                widget.onModeSelected(mode);
              },
              child: AnimatedBuilder(
                animation: _glowAnim,
                builder: (context, child) {
                  final glowValue =
                      isGlowing ? (1.0 - _glowAnim.value) * 0.6 : 0.0;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? mode.color.withValues(alpha: 0.18)
                          : onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? mode.color.withValues(alpha: 0.55)
                            : onSurface.withValues(alpha: 0.10),
                        width: isSelected ? 1.5 : 1,
                      ),
                      boxShadow: glowValue > 0.01
                          ? [
                              BoxShadow(
                                color: mode.color.withValues(alpha: glowValue),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Icon(
                            mode.icon,
                            key: ValueKey('${mode.name}-icon-$isSelected'),
                            size: 16,
                            color: isSelected
                                ? mode.color
                                : onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? mode.color
                                : onSurface.withValues(alpha: 0.5),
                          ),
                          child: Text(mode.label),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
