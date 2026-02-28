/// WebSocket message models mirroring the backend schemas.
class WsInbound {
  final String type;
  final String? data;
  final String? text;
  final String? mode;
  final String? sourceLang;
  final String? targetLang;
  final String? voice;
  final String? resumeSessionId;

  const WsInbound({
    required this.type,
    this.data,
    this.text,
    this.mode,
    this.sourceLang,
    this.targetLang,
    this.voice,
    this.resumeSessionId,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        if (data != null) 'data': data,
        if (text != null) 'text': text,
        if (mode != null) 'mode': mode,
        if (sourceLang != null) 'source_lang': sourceLang,
        if (targetLang != null) 'target_lang': targetLang,
        if (voice != null) 'voice': voice,
        if (resumeSessionId != null) 'resume_session_id': resumeSessionId,
        // timestamp injected by WebSocketService.send() for latency tracking
      };
}

class WsOutbound {
  final String type;
  final String? data;
  final String? text;
  final String? actionType;
  final Map<String, dynamic>? payload;
  final double? timestamp;

  const WsOutbound({
    required this.type,
    this.data,
    this.text,
    this.actionType,
    this.payload,
    this.timestamp,
  });

  factory WsOutbound.fromJson(Map<String, dynamic> json) => WsOutbound(
        type: json['type'] as String,
        data: json['data'] as String?,
        text: json['text'] as String?,
        actionType: json['action_type'] as String?,
        payload: json['payload'] as Map<String, dynamic>?,
        timestamp: (json['timestamp'] as num?)?.toDouble(),
      );
}
