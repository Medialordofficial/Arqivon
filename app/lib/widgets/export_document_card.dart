import 'package:flutter/material.dart';

import '../models/agent_mode.dart';
import '../services/export_service.dart';
import 'glassmorphic_card.dart';

/// A card shown when the AI generates an exportable document.
class ExportDocumentCard extends StatefulWidget {
  const ExportDocumentCard({
    super.key,
    required this.doc,
    this.onDismiss,
  });

  final ExportDocument doc;
  final VoidCallback? onDismiss;

  @override
  State<ExportDocumentCard> createState() => _ExportDocumentCardState();
}

class _ExportDocumentCardState extends State<ExportDocumentCard> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await ExportService.sharePdf(widget.doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassmorphicCard(
      blur: 25,
      opacity: 0.22,
      borderOpacity: 0.35,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C74A8).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded,
                    color: Color(0xFF7C74A8), size: 20),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C74A8).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'EXPORT READY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Color(0xFF7C74A8),
                  ),
                ),
              ),
              const Spacer(),
              if (widget.onDismiss != null)
                InkWell(
                  onTap: widget.onDismiss,
                  child: Icon(Icons.close,
                      size: 16, color: onSurface.withValues(alpha: 0.38)),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            widget.doc.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 6),

          // Preview
          Text(
            widget.doc.content.length > 200
                ? '${widget.doc.content.substring(0, 200)}…'
                : widget.doc.content,
            style: TextStyle(
              fontSize: 12,
              color: onSurface.withValues(alpha: 0.65),
              height: 1.4,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // Export button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_exporting ? 'Exporting…' : 'Export as PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C74A8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
