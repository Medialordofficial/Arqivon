import 'dart:io';

Future<void> main() async {
  final file = File('lib/services/audio_service.dart');
  var content = await file.readAsString();

  content = content.replaceAll(RegExp(r'import ''package:path_provider/path_provider.dart'';\n?'), '');

  // I will just use dart to output the whole new file to avoid regex complexities which always fail.
}
