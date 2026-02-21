import 'package:flutter/material.dart';

import '../models/agent_mode.dart';
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
    const map = {
      'auto': 'Auto',
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'pt': 'Portuguese',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'ru': 'Russian',
      'tr': 'Turkish',
      'nl': 'Dutch',
      'pl': 'Polish',
      'sv': 'Swedish',
      'th': 'Thai',
      'vi': 'Vietnamese',
    };
    return map[code] ?? code.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return GlassmorphicCard(
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AgentMode.translator.color.withOpacity(0.2),
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 14, color: Colors.white54),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AgentMode.translator.color.withOpacity(0.2),
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
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    overlay.formality,
                    style: const TextStyle(fontSize: 10, color: Colors.white60),
                  ),
                ),
              if (onDismiss != null)
                InkWell(
                  onTap: onDismiss,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.close, size: 16, color: Colors.white38),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Source text (original)
          Text(
            overlay.sourceText,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.3,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
