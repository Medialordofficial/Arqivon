import 'package:flutter/material.dart';

import '../models/agent_mode.dart';
import 'glassmorphic_card.dart';

/// Compact topic-trail chip shown during Support mode.
class SupportTopicTracker extends StatelessWidget {
  const SupportTopicTracker({
    super.key,
    required this.currentTopic,
    required this.allTopics,
  });

  final SupportTopic currentTopic;
  final List<SupportTopic> allTopics;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassmorphicCard(
      blur: 20,
      opacity: 0.18,
      borderOpacity: 0.25,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current topic
          Row(
            children: [
              Icon(Icons.support_agent_rounded,
                  size: 16, color: AgentMode.support.color),
              const SizedBox(width: 8),
              Text(
                'CURRENT TOPIC',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AgentMode.support.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            currentTopic.topic,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          if (currentTopic.reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              currentTopic.reason,
              style: TextStyle(
                fontSize: 11,
                color: onSurface.withValues(alpha: 0.5),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // Topic trail chips
          if (allTopics.length > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 26,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: allTopics.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final t = allTopics[index];
                  final isCurrent = index == allTopics.length - 1;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AgentMode.support.color.withValues(alpha: 0.2)
                          : onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: isCurrent
                          ? Border.all(
                              color: AgentMode.support.color
                                  .withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Text(
                      t.topic,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isCurrent
                            ? AgentMode.support.color
                            : onSurface.withValues(alpha: 0.54),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
