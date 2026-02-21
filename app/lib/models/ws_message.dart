/// WebSocket message models mirroring the backend schemas.
class WsInbound {
  final String type;
  final String? data;
  final String? text;
  final String? mode;
  final String? sourceLang;
  final String? targetLang;

  const WsInbound({
    required this.type,
    this.data,
    this.text,
    this.mode,
    this.sourceLang,
    this.targetLang,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        if (data != null) 'data': data,
        if (text != null) 'text': text,
        if (mode != null) 'mode': mode,
        if (sourceLang != null) 'source_lang': sourceLang,
        if (targetLang != null) 'target_lang': targetLang,
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
      };
}

class WsOutbound {
  final String type;
  final String? data;
  final String? text;
  final String? actionType;
  final Map<String, dynamic>? payload;

  const WsOutbound({
    required this.type,
    this.data,
    this.text,
    this.actionType,
    this.payload,
  });

  factory WsOutbound.fromJson(Map<String, dynamic> json) => WsOutbound(
        type: json['type'] as String,
        data: json['data'] as String?,
        text: json['text'] as String?,
        actionType: json['action_type'] as String?,
        payload: json['payload'] as Map<String, dynamic>?,
      );
}
