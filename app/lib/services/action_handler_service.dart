import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/smart_action.dart';

/// Executes real platform actions dispatched by Smart Action Cards.
///
/// Each action type maps to a concrete platform integration rather than
/// showing a placeholder snackbar.
class ActionHandlerService {
  ActionHandlerService._();

  /// Execute the primary action for a [SmartAction].
  /// Returns a user-facing result message.
  static Future<String> execute(
    SmartAction action,
    BuildContext context,
  ) async {
    switch (action.actionType) {
      case 'open_url':
        return _openUrl(action);
      case 'add_calendar':
        return _addCalendarEvent(action);
      case 'save_contact':
        return _saveContact(action);
      case 'save_note':
        return _saveNote(action);
      case 'add_reminder':
        return _addReminder(action);
      case 'share':
        return _share(action);
      case 'translate':
      case 'translation_card':
        return _copyTranslation(action);
      case 'escalate_case':
        return _escalateCase(action);
      case 'log_resolution':
        return _logResolution(action);
      case 'support_card':
        return _supportAction(action);
      default:
        return _genericAction(action);
    }
  }

  /// Open a URL in the system browser.
  static Future<String> _openUrl(SmartAction action) async {
    // Try to find URL in the description or title
    final text = '${action.title} ${action.description}';
    final urlRegex = RegExp(r'https?://[^\s]+');
    final match = urlRegex.firstMatch(text);
    final urlStr = match?.group(0) ?? action.description;

    final uri = Uri.tryParse(urlStr.trim());
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return 'Opened in browser';
    }

    // Fallback: search for the content
    final searchUri = Uri.parse(
      'https://www.google.com/search?q=${Uri.encodeComponent(action.title)}',
    );
    await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    return 'Searched for "${action.title}"';
  }

  /// Create a calendar event via platform intent.
  static Future<String> _addCalendarEvent(SmartAction action) async {
    // Build a calendar intent URI (works on both iOS and Android)
    final title = Uri.encodeComponent(action.title);
    final details = Uri.encodeComponent(action.description);

    // Try Google Calendar URL (most reliable cross-platform)
    final calUri = Uri.parse(
      'https://calendar.google.com/calendar/event?action=TEMPLATE'
      '&text=$title&details=$details',
    );
    if (await canLaunchUrl(calUri)) {
      await launchUrl(calUri, mode: LaunchMode.externalApplication);
      return 'Calendar event created';
    }
    return 'Could not open calendar';
  }

  /// Save contact info — copies to clipboard and offers to share.
  static Future<String> _saveContact(SmartAction action) async {
    final contactInfo = '${action.title}\n${action.description}';
    await Clipboard.setData(ClipboardData(text: contactInfo));
    await Share.share('Contact: $contactInfo');
    return 'Contact info shared';
  }

  /// Save a note — copy to clipboard.
  static Future<String> _saveNote(SmartAction action) async {
    final noteText = '${action.title}\n\n${action.description}';
    await Clipboard.setData(ClipboardData(text: noteText));
    return 'Note copied to clipboard';
  }

  /// Add a reminder — opens native reminder/calendar.
  static Future<String> _addReminder(SmartAction action) async {
    final title = Uri.encodeComponent(action.title);
    final details = Uri.encodeComponent(action.description);
    final calUri = Uri.parse(
      'https://calendar.google.com/calendar/event?action=TEMPLATE'
      '&text=$title&details=$details',
    );
    if (await canLaunchUrl(calUri)) {
      await launchUrl(calUri, mode: LaunchMode.externalApplication);
      return 'Reminder set';
    }
    // Fallback: copy to clipboard
    await Clipboard.setData(
      ClipboardData(text: 'Reminder: ${action.title}\n${action.description}'),
    );
    return 'Reminder copied to clipboard';
  }

  /// Share content via system share sheet.
  static Future<String> _share(SmartAction action) async {
    await Share.share(
      '${action.title}\n\n${action.description}\n\n— Shared via Arqivon',
    );
    return 'Shared';
  }

  /// Copy translation text to clipboard.
  static Future<String> _copyTranslation(SmartAction action) async {
    await Clipboard.setData(ClipboardData(text: action.description));
    return 'Translation copied to clipboard';
  }

  /// Escalate a support case — share the case details.
  static Future<String> _escalateCase(SmartAction action) async {
    await Share.share(
      'Escalated Case: ${action.title}\n\n${action.description}',
    );
    return 'Case escalated & shared';
  }

  /// Log a resolution — copy details.
  static Future<String> _logResolution(SmartAction action) async {
    await Clipboard.setData(
      ClipboardData(text: 'Resolution: ${action.title}\n${action.description}'),
    );
    return 'Resolution logged & copied';
  }

  /// Generic support card action.
  static Future<String> _supportAction(SmartAction action) async {
    await Clipboard.setData(
      ClipboardData(text: '${action.title}\n${action.description}'),
    );
    return 'Support info copied';
  }

  /// Fallback for unknown action types.
  static Future<String> _genericAction(SmartAction action) async {
    await Clipboard.setData(
      ClipboardData(text: '${action.title}\n${action.description}'),
    );
    return 'Action details copied';
  }
}
