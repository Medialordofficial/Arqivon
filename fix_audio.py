import re
with open("app/lib/services/audio_service.dart", "r") as f:
    orig = f.read()

parts = orig.split("class LivePcmStreamSource extends StreamAudioSource {")
if len(parts) != 2:
    print("Could not find class LivePcmStreamSource")
    exit(1)

new_class = """class LivePcmStreamSource extends StreamAudioSource {
  LivePcmStreamSource() {
    _controller = StreamController<List<int>>();
  }

  late final StreamController<List<int>> _controller;
  bool _closed = false;

  void addPcm(List<int> bytes) {
    if (_closed || bytes.isEmpty) return;
    _controller.add(bytes);
  }

  void closeTurn() {
    if (_closed) return;
    _closed = true;
    _controller.close();
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    return StreamAudioResponse(
      rangeRequestsSupported: false,
      sourceLength: null,
      contentLength: null,
      offset: 0,
      contentType: 'audio/wav',
      stream: _streamBytes(),
    );
  }

  Stream<List<int>> _streamBytes() async* {
    yield _wavHeader();
    yield* _controller.stream;
  }

  Uint8List _wavHeader({int sampleRate = 24000}) {
    final byteRate = sampleRate * 2;
    final header = ByteData(44);
    void writeString(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    // Using 0xffffffff instead of 0x7fffffff or exact size to indicate infinite live stream
    header.setUint32(4, 0xffffffff, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // 1 channel
    header.setUint32(24, sampleRate, Endian.little); // sample rate
    header.setUint32(28, byteRate, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    writeString(36, 'data');
    header.setUint32(40, 0xffffffff, Endian.little); // infinite data
    return header.buffer.asUint8List();
  }
}
"""

tail_idx = parts[1].find("/// Alias so the provider")
new_text = parts[0] + new_class + "\n" + (parts[1][tail_idx:] if tail_idx != -1 else "")

with open("app/lib/services/audio_service.dart", "w") as f:
    f.write(new_text)

print("Done fixing audio_service.dart")
