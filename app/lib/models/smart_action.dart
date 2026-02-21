/// Smart Action Card model dispatched by Gemini via create_ui_action.
class SmartAction {
  final String actionType;
  final String title;
  final String description;
  final String icon;
  final String primaryActionLabel;
  final DateTime receivedAt;

  SmartAction({
    required this.actionType,
    required this.title,
    this.description = '',
    this.icon = 'auto_awesome',
    this.primaryActionLabel = 'OK',
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  factory SmartAction.fromPayload(
          String actionType, Map<String, dynamic> payload) =>
      SmartAction(
        actionType: actionType,
        title: payload['title'] as String? ?? actionType,
        description: payload['description'] as String? ?? '',
        icon: payload['icon'] as String? ?? 'auto_awesome',
        primaryActionLabel: payload['primary_action_label'] as String? ?? 'OK',
      );
}
