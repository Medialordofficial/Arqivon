import 'package:flutter/material.dart';

import '../models/agent_mode.dart';
import '../providers/settings_provider.dart';
import 'glassmorphic_card.dart';

/// Real-time translation subtitle overlay shown during Translator mode.
class TranslationOverlayWidget extends StatelessWidget {
  const TranslationOverlayWidget({
    super.key,
    required this.overlay,
    this.onDismiss,
  });

  final TranslationOverlay overlay;
  final VoidCallback? onDismiss;

  String _langLabel(String code) {
    return availableLanguages[code] ?? code.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label:
          'Translation: ${_langLabel(overlay.sourceLanguage)} to ${_langLabel(overlay.targetLanguage)}',
      child: GlassmorphicCard(
        blur: 30,
        opacity: 0.25,
        borderOpacity: 0.4,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Language direction header
            Row(
              children: [
                Icon(Icons.translate_rounded,
                    size: 18, color: AgentMode.translator.color),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AgentMode.translator.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _langLabel(overlay.sourceLanguage),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AgentMode.translator.color,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 14, color: onSurface.withValues(alpha: 0.54)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AgentMode.translator.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _langLabel(overlay.targetLanguage),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AgentMode.translator.color,
                    ),
                  ),
                ),
                const Spacer(),
                if (overlay.formality != 'neutral')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      overlay.formality,
                      style: TextStyle(
                          fontSize: 10,
                          color: onSurface.withValues(alpha: 0.6)),
                    ),
                  ),
                if (onDismiss != null)
                  InkWell(
                    onTap: onDismiss,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.close,
                          size: 16, color: onSurface.withValues(alpha: 0.38)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Source text (original)
            Text(
              overlay.sourceText,
              style: TextStyle(
                fontSize: 14,
                color: onSurface.withValues(alpha: 0.7),
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (overlay.translatedText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                overlay.translatedText,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                  height: 1.3,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
