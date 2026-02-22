import 'package:flutter/material.dart';

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

          return GestureDetector(
            onTap: () => onModeSelected(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? mode.color.withOpacity(0.15)
                    : const Color(0xFF0F172A).withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? mode.color.withOpacity(0.5)
                      : const Color(0xFF0F172A).withOpacity(0.10),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    mode.icon,
                    size: 16,
                    color: isSelected ? mode.color : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? mode.color : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
