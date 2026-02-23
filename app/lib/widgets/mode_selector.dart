import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent_mode.dart';

/// Horizontal mode-picker strips shown at the top of Live screen.
class ModeSelectorStrip extends StatelessWidget {
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
          final isSelected = mode == selectedMode;

          return Semantics(
            label: '${mode.label} mode${isSelected ? ", selected" : ""}',
            button: true,
            selected: isSelected,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onModeSelected(mode);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? mode.color.withValues(alpha: 0.15)
                      : onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? mode.color.withValues(alpha: 0.5)
                        : onSurface.withValues(alpha: 0.10),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      mode.icon,
                      size: 16,
                      color: isSelected
                          ? mode.color
                          : onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      mode.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? mode.color
                            : onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
